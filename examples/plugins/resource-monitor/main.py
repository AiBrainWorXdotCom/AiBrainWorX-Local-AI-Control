"""Optional API-1 resource monitor. Python standard library; no HTTP requests.

Light samples reuse launcher-supplied Strata metrics. OS process inspection runs
only after an explicit inspectProcesses=true request. No command lines, full
executable paths, environment variables or window titles are read or returned.
"""
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def number(value, maximum=10**18):
    return value if type(value) in (int, float) and 0 <= value <= maximum and math.isfinite(value) else None


def process_name(value):
    # comm and PerfProc Name are names, not command lines. Keep output to a
    # conservative basename alphabet so unusual process names cannot look like
    # shell invocations or disclose paths in a panel.
    return value if isinstance(value, str) and re.fullmatch(r'[\w.()+-]{1,64}', value, re.ASCII) else 'process'


def linux_snapshot():
    total = idle = None
    try:
        cpu = [int(value) for value in Path('/proc/stat').read_text().splitlines()[0].split()[1:9]]
        total, idle = sum(cpu), cpu[3] + (cpu[4] if len(cpu) > 4 else 0)
    except (OSError, ValueError, IndexError):
        pass
    rows = {}
    try:
        directories = sorted((entry for entry in Path('/proc').iterdir() if entry.name.isdigit()), key=lambda entry: int(entry.name))[:4096]
    except OSError:
        directories = []
    page_size = os.sysconf('SC_PAGE_SIZE')
    for directory in directories:
        try:
            stat = (directory/'stat').read_text()
            begin, end = stat.index('('), stat.rindex(')')
            fields = stat[end+2:].split()  # starts at field 3, process state
            rows[int(directory.name)] = {'name': process_name(stat[begin+1:end]),
                                         'ticks': int(fields[11])+int(fields[12]),
                                         'memoryBytes': max(0, int(fields[21]))*page_size}
        except (OSError, ValueError, IndexError):
            continue  # process exited or /proc is restricted
    return total, idle, rows


def linux_processes():
    before_total, before_idle, before = linux_snapshot()
    time.sleep(.12)
    after_total, after_idle, after = linux_snapshot()
    delta = after_total-before_total if after_total is not None and before_total is not None else 0
    rows = []
    for pid, item in after.items():
        old = before.get(pid)
        cpu = min(100.0, max(0.0, (item['ticks']-old['ticks'])*100/delta)) if old and delta > 0 and item['ticks'] >= old['ticks'] else None
        rows.append({'pid': pid, 'name': item['name'], 'cpuPercent': cpu, 'memoryBytes': item['memoryBytes']})
    hardware = {'cpu': min(100.0, max(0.0, 100*(delta-(after_idle-before_idle))/delta)) if delta > 0 else None}
    try:
        memory = {key: int(value.split()[0])*1024 for line in Path('/proc/meminfo').read_text().splitlines() if ':' in line for key, value in [line.split(':', 1)]}
        hardware['ram_total'] = memory.get('MemTotal')
        hardware['ram_used'] = memory['MemTotal']-memory['MemAvailable'] if 'MemTotal' in memory and 'MemAvailable' in memory else None
    except (OSError, ValueError):
        pass
    return rows, hardware


def windows_processes():
    # Fixed read-only CIM fields. The bounded hidden child never asks WMI for
    # CommandLine, ExecutablePath, Environment or a window title.
    script = r"""$ErrorActionPreference='Stop'
$rows=@(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Property IDProcess,Name,PercentProcessorTime,WorkingSetPrivate | Where-Object {$_.IDProcess -gt 0 -and $_.Name -ne '_Total'} | Sort-Object WorkingSetPrivate -Descending | Select-Object -First 20 IDProcess,Name,PercentProcessorTime,WorkingSetPrivate)
$os=Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize,FreePhysicalMemory
$cpu=Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -Property PercentProcessorTime | Select-Object -First 1 -ExpandProperty PercentProcessorTime
@{rows=$rows;total=$os.TotalVisibleMemorySize;free=$os.FreePhysicalMemory;cpu=$cpu} | ConvertTo-Json -Compress -Depth 4
"""
    powershell = Path(os.environ.get('SystemRoot', r'C:\Windows'))/'System32/WindowsPowerShell/v1.0/powershell.exe'
    result = subprocess.run([str(powershell), '-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
                            capture_output=True, text=True, encoding='utf-8', timeout=3.2, check=True,
                            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    if len(result.stdout) > 32768:
        raise ValueError('Process sample too large.')
    data = json.loads(result.stdout)
    rows = []
    for item in data.get('rows', [])[:20]:
        pid = number(item.get('IDProcess'), 2**31-1)
        if pid is None or pid < 1:
            continue
        cpu = number(item.get('PercentProcessorTime'))
        rows.append({'pid': int(pid), 'name': process_name(item.get('Name')),
                     'cpuPercent': min(100.0, cpu/max(1, os.cpu_count() or 1)) if cpu is not None else None,
                     'memoryBytes': number(item.get('WorkingSetPrivate'), 2**63-1)})
    total, free = number(data.get('total')), number(data.get('free'))
    return rows, {'cpu': number(data.get('cpu'), 100), 'ram_total': total*1024 if total is not None else None,
                  'ram_used': (total-free)*1024 if total is not None and free is not None and total >= free else None}


def gpu_memory():
    # Optional compute-process allocation only. Missing utility, unsupported
    # driver, permission errors and absent PID measurements remain unknown.
    executable = shutil.which('nvidia-smi')
    if not executable and os.name == 'nt':
        candidate = Path(os.environ.get('SystemRoot', r'C:\Windows'))/'System32/nvidia-smi.exe'
        executable = str(candidate) if candidate.is_file() else None
    if not executable:
        return {}
    try:
        result = subprocess.run([executable, '--query-compute-apps=pid,used_gpu_memory', '--format=csv,noheader,nounits'],
                                capture_output=True, text=True, timeout=.8, check=True,
                                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if len(result.stdout) > 32768:
            return {}
        values = {}
        for line in result.stdout.splitlines()[:4096]:
            fields = line.split(',')
            if len(fields) == 2 and fields[0].strip().isdigit() and fields[1].strip().isdigit():
                pid, mib = int(fields[0]), int(fields[1])
                if 0 < pid < 2**31 and mib < 2**40:
                    values[pid] = values.get(pid, 0) + mib*1024*1024
        return values
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}


def sample(context):
    context = context if isinstance(context, dict) else {}
    supplied = context.get('modelMetrics')
    telemetry = supplied if isinstance(supplied, dict) else {}
    hardware = telemetry.get('hardware') if isinstance(telemetry.get('hardware'), dict) else {}
    live = telemetry.get('live') if isinstance(telemetry.get('live'), dict) else {}
    requests = telemetry.get('requests')
    last = requests[0] if isinstance(requests, list) and requests and isinstance(requests[0], dict) else {}
    rows, observed = [], {}
    note = 'Existing model telemetry only. Process inspection is off.'
    if context.get('inspectProcesses') is True:
        try:
            if sys.platform == 'win32':
                rows, observed = windows_processes()
            elif sys.platform.startswith('linux'):
                rows, observed = linux_processes()
            else:
                note = 'Process inspection is unavailable on this operating system.'
            if sys.platform == 'win32' or sys.platform.startswith('linux'):
                note = 'Read-only process sample. Unavailable measurements show N/A. No process controls.'
            rows = sorted(rows, key=lambda row: (row.get('memoryBytes') or 0), reverse=True)[:20]
            if context.get('includeGpuProcesses') is True:
                gpu = gpu_memory()
                for row in rows:
                    row['gpuMemoryBytes'] = gpu.get(row['pid'])
        except (OSError, ValueError, TypeError, subprocess.SubprocessError):
            rows, observed = [], {}
            note = 'Process inspection is unavailable or timed out. Existing model telemetry remains visible.'
    def metric(label, key, unit):
        value = number(hardware.get(key))
        if value is None:
            value = number(observed.get(key))
        return {'label': label, 'value': value, 'unit': unit, 'state': 'ok' if value is not None else 'unavailable'}
    metrics = [metric('CPU usage', 'cpu', '%'), metric('RAM used', 'ram_used', 'bytes'),
               metric('RAM total', 'ram_total', 'bytes'), metric('GPU memory used', 'gpu_mem_used', 'bytes'),
               metric('GPU memory total', 'gpu_mem_total', 'bytes')]
    decode = number(live.get('tok_s')) if live.get('state') == 'generating' else number(last.get('decode_tok_s'))
    prompt_ms, prompt_read = number(last.get('prompt_ms')), number(last.get('prompt_read'))
    for label, value, unit in [('Decode rate', decode, 'tokens/s'),
                               ('Prompt processing', prompt_read*1000/prompt_ms if prompt_ms and prompt_read is not None else None, 'tokens/s'),
                               ('First token', number(last.get('first_engine_token_s')), 's')]:
        value = number(value)
        metrics.append({'label': label, 'value': value, 'unit': unit, 'state': 'ok' if value is not None else 'unavailable'})
    backend = context.get('backend')
    name = {'strata': 'Strata', 'ollama': 'Ollama', 'lmstudio': 'LM Studio', 'compatible': 'Local model'}.get(backend, 'Local model')
    state = live.get('state') if live.get('state') in ('idle', 'generating', 'running', 'stopped', 'error') else 'available' if supplied is not None else 'unknown'
    return {'metrics': metrics, 'services': [{'name': name, 'state': state,
             'detail': 'Existing launcher telemetry' if supplied is not None else 'Model telemetry unavailable'}], 'processes': rows, 'note': note}


def main():
    request = json.load(sys.stdin)
    if request.get('apiVersion') != 1 or request.get('hook') != 'monitor.sample':
        raise ValueError('Unsupported event.')
    print(json.dumps({'apiVersion': 1, 'panel': sample(request.get('context'))}, allow_nan=False))


if __name__ == '__main__':
    main()

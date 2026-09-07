#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import re
import subprocess
import sys

VCS_OPTS = [
    'vcs', '+v2k', '-timescale=1ns/1ps',
    '-full64', '-debug_access+all', '-f', 'filelist.f',
    '+mindelays', '-negdelay', '+neg_tchk',
    '-cm', 'line+cond+tgl+fsm',
    '--log=compile.log', '+incdir+../rtl/header',
]
SIMV = './simv'
CM_OPTS = ['-cm', 'line+cond+tgl+fsm']
BIN_DIR = '../tests/isa/generated'
ROM_WORDS = 256


def list_binfiles(path):
    files = []
    for maindir, subdir, all_file in os.walk(path):
        for filename in all_file:
            apath = os.path.join(maindir, filename)
            if apath.endswith('.bin'):
                files.append(apath)
    return files


def main():
    bin_files = sorted(list_binfiles(BIN_DIR))

    if not os.path.exists(SIMV):
        print('Compiling with VCS ...')
        r = subprocess.run(VCS_OPTS)
        if r.returncode != 0:
            print('VCS compile FAILED, see compile.log')
            return 1

    anyfail = False
    skipped = 0
    for file in bin_files:
        size = os.path.getsize(file)
        if size > ROM_WORDS * 4:
            print(f'{file}    SKIP (bin {size}B > ROM {ROM_WORDS} words)')
            skipped += 1
            continue

        subprocess.run(['python', 'generate_inst_data.py', file], check=True)
        name = os.path.basename(file).replace('.bin', '')
        log = f'run_{name}.log'
        r = subprocess.run([SIMV, '--log=' + log] + CM_OPTS + ['-cm_name', name])
        if r.returncode != 0:
            print(file + '    !!!SIM FAIL!!!')
            anyfail = True
            continue

        with open(log, encoding='utf-8', errors='replace') as f:
            content = f.read()
        if 'TEST_PASS' in content:
            print(file + '    PASS')
        elif 'Time Out.' in content or 'Time Out' in content:
            print(file + '    TIME_OUT')
        else:
            print(file + '    !!!FAIL!!!')
            anyfail = True

    print()
    print(f'Done: {len(bin_files)} bins, {skipped} skipped (ROM overflow), '
          + ('FAIL found !!!' if anyfail else 'All PASS ...'))

    # merge coverage and generate HTML report
    print()
    print('Merging coverage with urg ...')
    r = subprocess.run(['urg', '-dir', 'simv.vdb', '-reportdir', 'cov_report', '-assert',
                        '--log=urg.log'])
    if r.returncode != 0:
        print('urg FAILED, see urg.log')
    else:
        report = os.path.join('cov_report', 'coverReport.html')
        if os.path.exists(report):
            print(f'Coverage report: {os.path.abspath(report)}')
            print('Open it with: xdg-open cov_report/coverReport.html (or any browser)')

    return 1 if anyfail else 0


if __name__ == '__main__':
    sys.exit(main())

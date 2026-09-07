import sys
import filecmp
import subprocess
import sys
import os


# 主函数
def main():
    #print(sys.argv[0] + ' ' + sys.argv[1] + ' ' + sys.argv[2])

    # 1.将bin文件转成mem文件
    cmd = r'python ../tools/BinToMem_CLI.py' + ' ' + sys.argv[1] + ' ' + sys.argv[2]
    f = os.popen(cmd)
    f.close()

    # 2.编译rtl文件
    cmd = r'python compile_rtl.py' + r' ..'
    f = os.popen(cmd)
    f.close()

    # SIM_TOOL=uvs 时启用 uvs/uvsim 流程，默认保持原有 vvp 流程
    use_uvs = (os.environ.get('SIM_TOOL') == 'uvs')

    # 3.运行
    if use_uvs:
        testname = os.path.splitext(os.path.basename(sys.argv[1]))[0]
        uvsim_cmd = [r'./uvsim']
        uvsim_cmd += ['-cov', r'stmt,cond,tgl,fsm,assert']
        uvsim_cmd += ['-covtest', testname]
        uvsim_cmd += ['-logfile', r'run_uvs.log']
        process = subprocess.Popen(uvsim_cmd)
    else:
        vvp_cmd = [r'vvp']
        vvp_cmd.append(r'out.vvp')
        process = subprocess.Popen(vvp_cmd)
    try:
        process.wait(timeout=(300 if use_uvs else 30))
    except subprocess.TimeoutExpired:
        print('!!!Fail, vvp exec timeout!!!')


if __name__ == '__main__':
    sys.exit(main())

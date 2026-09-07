import sys
import filecmp
import subprocess
import sys
import os


# 主函数
def main():

    filename = sys.argv[1]
    file_extension = os.path.splitext(filename)[1]

    if file_extension == ".bin":
        cmd = r'python ../tools/BinToMem_CLI.py' + ' ' + sys.argv[1] + ' ' + r'inst.data'
        f = os.popen(cmd)
        f.close()
    elif file_extension == ".data":
        # 1.copy目标Mem文件到本地
        cmd = r'cp' + ' ' + sys.argv[1] + ' ' + r'inst.data'
        f = os.popen(cmd)
        f.close()
    else:
        print("Usage: provide .bin or .data")
        sys.exit(1)

    # 2.编译rtl文件
    cmd = r'python compile_rtl.py' + r' ..'
    f = os.popen(cmd)
    f.close()

    # SIM_TOOL=uvs 时启用 uvs/uvsim 流程，默认保持原有 vvp 流程
    use_uvs = (os.environ.get('SIM_TOOL') == 'uvs')

    # 3.运行
    if use_uvs:
        testname = os.path.splitext(os.path.basename(filename))[0]
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
        process.wait(timeout=(300 if use_uvs else 20))
    except subprocess.TimeoutExpired:
        print('!!!Fail, vvp exec timeout!!!')


if __name__ == '__main__':
    sys.exit(main())
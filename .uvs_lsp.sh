#!/usr/bin/env bash
set -euo pipefail
# NOTE: This script is generated for LSP compile purpose only.
# It is NOT a general-purpose compile script.
# Do NOT use it if you want to compile the design and get an executable.

__dump_invocation_argv0='/big_disk/uv-tools/UVS_2026.06.P2.Beta/bin/uvlog2'
__dump_invocation_exe='/big_disk/uv-tools/UVS_2026.06.P2.Beta/bin/uvlog2'
declare +x __dump_invocation_argv0 __dump_invocation_exe __dump_invocation_name 2>/dev/null || true
__dump_invocation_args=(
  '-sv'
  '-uvm1.2'
  '-timescale'
  '1ns/1ps'
  '-define'
  'SIMULATION'
  '-define'
  'UVM_NO_DEPRECATED'
  '-include'
  'rtl/cache'
  '-include'
  'rtl/common'
  '-include'
  'tb/uvm_tb/agents/axi_agent'
  '-include'
  'tb/uvm_tb/agents/ace_snoop_agent'
  '-include'
  'tb/uvm_tb/ref_model'
  '-include'
  'tb/uvm_tb/sequences'
  '-include'
  'tb/uvm_tb/scoreboard'
  '-include'
  'tb/uvm_tb/coverage'
  '-include'
  'tb/uvm_tb/env'
  '-include'
  'tb/uvm_tb/tests'
  '-include'
  'tb/assertions'
  '-include'
  'scripts/cdc'
  'rtl/cache/l2_axi_master.sv'
  'rtl/cache/l2_cache_pkg.sv'
  'rtl/cache/l2_cache_top.sv'
  'rtl/cache/l2_coherency_fsm.sv'
  'rtl/cache/l2_data_array.sv'
  'rtl/cache/l2_ecc_engine.sv'
  'rtl/cache/l2_hit_miss_detect.sv'
  'rtl/cache/l2_lru_controller.sv'
  'rtl/cache/l2_mshr.sv'
  'rtl/cache/l2_perf_counters.sv'
  'rtl/cache/l2_prefetch_engine.sv'
  'rtl/cache/l2_request_pipeline.sv'
  'rtl/cache/l2_tag_array.sv'
  'rtl/common/async_fifo.sv'
  'rtl/common/rr_arbiter.sv'
  'rtl/common/sync_fifo.sv'
  'tb/uvm_tb/agents/axi_agent/axi_slave_agent.sv'
  'tb/uvm_tb/agents/axi_agent/axi_master_agent.sv'
  'tb/uvm_tb/agents/ace_snoop_agent/ace_snoop_agent.sv'
  'tb/uvm_tb/sequences/l2_seq_items.sv'
  'tb/uvm_tb/sequences/l2_coherency_seq.sv'
  'tb/uvm_tb/ref_model/l2_ref_model.sv'
  'tb/uvm_tb/scoreboard/l2_scoreboard.sv'
  'tb/uvm_tb/coverage/l2_coverage.sv'
  'tb/uvm_tb/env/l2_cache_env.sv'
  'tb/uvm_tb/tests/l2_tests.sv'
  'tb/uvm_tb/tests/l2_tests_extended.sv'
  'tb/uvm_tb/tests/directed/l2_ecc_test.sv'
  'tb/uvm_tb/tests/directed/l2_cdc_power_test.sv'
  'tb/uvm_tb/tests/directed/l2_performance_test.sv'
  'tb/assertions/l2_cache_assertions.sv'
  'tb/top/l2_cache_tb_top.sv'
  '-debug'
  'all'
  '-o'
  '/tmp/uda-8903/tbchk/uvsim'
  '-ddb'
  '-icomp'
  '-lsp_compile'
  '-o'
  '.uvsim.cache'
)

cd -- '/home/qlzheng/17-l2_cache_RTL_FV_TB_UVM_DFT'

if [[ "$(/usr/bin/env --help 2>/dev/null || true)" == *"--argv0"* ]]; then
  exec /usr/bin/env -i \
    --argv0="$__dump_invocation_argv0" \
    -- \
    'UVD_HOME=/big_disk/uv-tools/UVD_2026.06.P2.Beta' \
    'CONDA_SHLVL=1' \
    'NVM_DIR=/big_disk/dev-tools/nvm' \
    'CONDA_EXE=/big_disk/dev-tools/miniconda3/bin/conda' \
    'VSCODE_NLS_CONFIG={"userLocale":"en","osLocale":"en","resolvedLanguage":"en","defaultMessagesFile":"/home/qlzheng/.vscode-server/cli/servers/Stable-4fe60c8b1cdac1c4c174f2fb180d0d758272d713/server/out/nls.messages.json","locale":"en","availableLanguages":{}}' \
    'SSH_CONNECTION=10.170.24.2 51067 10.156.106.1 6890' \
    'UVS_HOME=/big_disk/uv-tools/UVS_2026.06.P2.Beta' \
    'LANG=en_US.UTF-8' \
    'HISTCONTROL=ignoredups' \
    'UDA_APP_NAME=uda' \
    'DISPLAY=localhost:11.0' \
    'UDA_SERVER_HOST=http://10.156.106.1:10003' \
    'HOSTNAME=shdmz-llm' \
    'OLDPWD=/home/qlzheng' \
    'NVM_CD_FLAGS=' \
    'GOPROXY=https://goproxy.cn,direct' \
    'CONDA_PREFIX=/big_disk/dev-tools/miniconda3' \
    'npm_config_user_agent=npm/undefined node/v24.3.0 linux x64 workspaces/false' \
    'OPENCODE=1' \
    'UDA_EDITOR_NAME=Visual Studio Code' \
    '_CE_M=' \
    'which_declare=declare -f' \
    'UDA_PROCESS_ROLE=main' \
    'UDA_PID=415373' \
    'XDG_SESSION_ID=15292' \
    'UDA_EXPERIMENTAL_DISABLE_FILEWATCHER=true' \
    'USER=qlzheng' \
    'UDA_PLATFORM=vscode' \
    'VSCODE_RECONNECTION_GRACE_TIME=10800000' \
    'UDA_PARENT_PID=414766' \
    'UDA_RUN_ID=e394b21d-1e66-4e7c-a53a-38b1513da232' \
    'UDA_TELEMETRY_LEVEL=all' \
    'UDA_TREE_SITTER_WASM_DIR=/home/qlzheng/.vscode-server/extensions/univista.univista-design-agent-0.0.0-dev.f53bba8b/bin/tree-sitter' \
    'GOPATH=/home/qlzheng/gopath' \
    'UDACODE_VERSION=0.0.0-dev.f53bba8b' \
    'UDA=1' \
    'PWD=/home/qlzheng/17-l2_cache_RTL_FV_TB_UVM_DFT' \
    'SSH_ASKPASS=/usr/libexec/openssh/gnome-ssh-askpass' \
    'HOME=/home/qlzheng' \
    'GOROOT=/big_disk/dev-tools/go/go1.19.9' \
    'CONDA_PYTHON_EXE=/big_disk/dev-tools/miniconda3/bin/python' \
    'BROWSER=/home/qlzheng/.vscode-server/cli/servers/Stable-4fe60c8b1cdac1c4c174f2fb180d0d758272d713/server/bin/helpers/browser.sh' \
    'SSH_CLIENT=10.170.24.2 51067 6890' \
    'YOSYS_PATH=/big_disk/dev-tools/oss-cad-suite/bin/yosys' \
    'XDG_DATA_DIRS=/home/qlzheng/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share' \
    'AGENT=1' \
    'VSCODE_CWD=/home/qlzheng' \
    'MIMALLOC_PURGE_DELAY=0' \
    '_CE_CONDA=' \
    'VSCODE_IPC_HOOK_CLI=/run/user/8903/vscode-ipc-01216beb-0792-4ae1-8db6-544cba5ea011.sock' \
    'UDA_DISABLE_CLAUDE_CODE=true' \
    'VSCODE_ESM_ENTRYPOINT=vs/workbench/api/node/extensionHostProcess' \
    'UV_LICENSE=8273@10.156.106.1' \
    'UVEC_HOME=/big_disk/uv-tools/UVEC_2025.06.P5' \
    'CONDA_PROMPT_MODIFIER=(base) ' \
    'VSCODE_HANDLES_SIGPIPE=true' \
    'VSCODE_CLI_REQUIRE_TOKEN=7f84b32c-27c2-4b35-a449-eb30ff75b102' \
    'MAIL=/var/spool/mail/qlzheng' \
    'UDACODE_FEATURE=vscode-extension' \
    'SHELL=/bin/bash' \
    'VSCODE_HANDLES_UNCAUGHT_ERRORS=true' \
    'UDA_MACHINE_ID=dba7dab19c316577a39b83040d8fc4c8723bddca5411087fded64717016cbe9f' \
    'NVM_BIN=/big_disk/dev-tools/nvm/versions/node/v22.23.0/bin' \
    'UDA_CLIENT=vscode' \
    'ELECTRON_RUN_AS_NODE=1' \
    'SHLVL=5' \
    'UVMC_HOME=/big_disk/uv-tools/UVMC_2026.06.P2.Beta' \
    'UDA_APP_VERSION=0.0.0-dev.f53bba8b' \
    'VSCODE_AGENT_FOLDER=/home/qlzheng/.vscode-server' \
    'UDA_DISABLE_CHANNEL_DB=true' \
    'UVH_HOME=/big_disk/uv-tools/UVH_2025.06.P4' \
    'LOGNAME=qlzheng' \
    'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/8903/bus' \
    'XDG_RUNTIME_DIR=/run/user/8903' \
    'PATH=/home/qlzheng/.vscode-server/extensions/univista.univista-design-agent-0.0.0-dev.f53bba8b/bin:/home/qlzheng/.vscode-server/cli/servers/Stable-4fe60c8b1cdac1c4c174f2fb180d0d758272d713/server/bin/remote-cli:/big_disk/uv-tools/UVMC_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVS_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVD_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVH_2025.06.P4/bin:/big_disk/uv-tools/UVEC_2025.06.P5/bin:/big_disk/uv-tools/vpslite/VPSlite_2025.09_20260527:/home/qlzheng/uda-linux-x64:/usr/local/zig-x86_64-linux-0.16.0:/big_disk/uv-tools/UVMC_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVS_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVD_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVH_2025.06.P4/bin:/big_disk/uv-tools/UVEC_2025.06.P5/bin:/big_disk/uv-tools/vpslite/VPSlite_2025.09_20260527:/big_disk/dev-tools/miniconda3/bin:/big_disk/dev-tools/miniconda3/condabin:/big_disk/dev-tools/nvm/versions/node/v22.23.0/bin:/home/qlzheng/uda-linux-x64:/home/qlzheng/.local/bin:/home/qlzheng/bin:/usr/local/zig-x86_64-linux-0.16.0:/home/qlzheng/.local/npm/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/big_disk/dev-tools/go/go1.19.9/bin:/home/qlzheng/gopath/bin:/home/qlzheng/uda-linux-x64:/big_disk/dev-tools/go/go1.19.9/bin:/home/qlzheng/gopath/bin:/home/qlzheng/uda-linux-x64' \
    'UDA_VSCODE_VERSION=1.127.0' \
    'NODE_USE_SYSTEM_CA=1' \
    'DEBUGINFOD_URLS=https://debuginfod.centos.org/ ' \
    'CONDA_DEFAULT_ENV=base' \
    'NVM_INC=/big_disk/dev-tools/nvm/versions/node/v22.23.0/include/node' \
    'HISTSIZE=1000' \
    'VPS_HOME=/big_disk/uv-tools/vpslite/VPSlite_2025.09_20260527' \
    'UDACODE_EDITOR_NAME=Visual Studio Code 1.127.0' \
    'APPLICATION_INSIGHTS_NO_STATSBEAT=true' \
    'LESSOPEN=||/usr/bin/lesspipe.sh %s' \
    'UDA_ENABLE_QUESTION_TOOL=true' \
    'BASH_FUNC_which%%=() {  ( alias;
 eval ${which_declare} ) | /usr/bin/which --tty-only --read-alias --read-functions --show-tilde --show-dot $@
}' \
    "$__dump_invocation_exe" \
    "${__dump_invocation_args[@]}"
fi

exec /usr/bin/env -i \
  -- \
  'PATH=/usr/bin:/bin' \
  perl \
  -e 'my $envc = shift @ARGV;
%ENV = ();
for (1 .. $envc) {
    my $entry = shift @ARGV;
    my ($name, $value) = split(/=/, $entry, 2);
    $ENV{$name} = $value;
}
my $exe = shift @ARGV;
my $argc = shift @ARGV;
my @argv = splice(@ARGV, 0, $argc);
exec { $exe } @argv;
die "exec $exe: $!\n";
' \
  '87' \
  'UVD_HOME=/big_disk/uv-tools/UVD_2026.06.P2.Beta' \
  'CONDA_SHLVL=1' \
  'NVM_DIR=/big_disk/dev-tools/nvm' \
  'CONDA_EXE=/big_disk/dev-tools/miniconda3/bin/conda' \
  'VSCODE_NLS_CONFIG={"userLocale":"en","osLocale":"en","resolvedLanguage":"en","defaultMessagesFile":"/home/qlzheng/.vscode-server/cli/servers/Stable-4fe60c8b1cdac1c4c174f2fb180d0d758272d713/server/out/nls.messages.json","locale":"en","availableLanguages":{}}' \
  'SSH_CONNECTION=10.170.24.2 51067 10.156.106.1 6890' \
  'UVS_HOME=/big_disk/uv-tools/UVS_2026.06.P2.Beta' \
  'LANG=en_US.UTF-8' \
  'HISTCONTROL=ignoredups' \
  'UDA_APP_NAME=uda' \
  'DISPLAY=localhost:11.0' \
  'UDA_SERVER_HOST=http://10.156.106.1:10003' \
  'HOSTNAME=shdmz-llm' \
  'OLDPWD=/home/qlzheng' \
  'NVM_CD_FLAGS=' \
  'GOPROXY=https://goproxy.cn,direct' \
  'CONDA_PREFIX=/big_disk/dev-tools/miniconda3' \
  'npm_config_user_agent=npm/undefined node/v24.3.0 linux x64 workspaces/false' \
  'OPENCODE=1' \
  'UDA_EDITOR_NAME=Visual Studio Code' \
  '_CE_M=' \
  'which_declare=declare -f' \
  'UDA_PROCESS_ROLE=main' \
  'UDA_PID=415373' \
  'XDG_SESSION_ID=15292' \
  'UDA_EXPERIMENTAL_DISABLE_FILEWATCHER=true' \
  'USER=qlzheng' \
  'UDA_PLATFORM=vscode' \
  'VSCODE_RECONNECTION_GRACE_TIME=10800000' \
  'UDA_PARENT_PID=414766' \
  'UDA_RUN_ID=e394b21d-1e66-4e7c-a53a-38b1513da232' \
  'UDA_TELEMETRY_LEVEL=all' \
  'UDA_TREE_SITTER_WASM_DIR=/home/qlzheng/.vscode-server/extensions/univista.univista-design-agent-0.0.0-dev.f53bba8b/bin/tree-sitter' \
  'GOPATH=/home/qlzheng/gopath' \
  'UDACODE_VERSION=0.0.0-dev.f53bba8b' \
  'UDA=1' \
  'PWD=/home/qlzheng/17-l2_cache_RTL_FV_TB_UVM_DFT' \
  'SSH_ASKPASS=/usr/libexec/openssh/gnome-ssh-askpass' \
  'HOME=/home/qlzheng' \
  'GOROOT=/big_disk/dev-tools/go/go1.19.9' \
  'CONDA_PYTHON_EXE=/big_disk/dev-tools/miniconda3/bin/python' \
  'BROWSER=/home/qlzheng/.vscode-server/cli/servers/Stable-4fe60c8b1cdac1c4c174f2fb180d0d758272d713/server/bin/helpers/browser.sh' \
  'SSH_CLIENT=10.170.24.2 51067 6890' \
  'YOSYS_PATH=/big_disk/dev-tools/oss-cad-suite/bin/yosys' \
  'XDG_DATA_DIRS=/home/qlzheng/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share' \
  'AGENT=1' \
  'VSCODE_CWD=/home/qlzheng' \
  'MIMALLOC_PURGE_DELAY=0' \
  '_CE_CONDA=' \
  'VSCODE_IPC_HOOK_CLI=/run/user/8903/vscode-ipc-01216beb-0792-4ae1-8db6-544cba5ea011.sock' \
  'UDA_DISABLE_CLAUDE_CODE=true' \
  'VSCODE_ESM_ENTRYPOINT=vs/workbench/api/node/extensionHostProcess' \
  'UV_LICENSE=8273@10.156.106.1' \
  'UVEC_HOME=/big_disk/uv-tools/UVEC_2025.06.P5' \
  'CONDA_PROMPT_MODIFIER=(base) ' \
  'VSCODE_HANDLES_SIGPIPE=true' \
  'VSCODE_CLI_REQUIRE_TOKEN=7f84b32c-27c2-4b35-a449-eb30ff75b102' \
  'MAIL=/var/spool/mail/qlzheng' \
  'UDACODE_FEATURE=vscode-extension' \
  'SHELL=/bin/bash' \
  'VSCODE_HANDLES_UNCAUGHT_ERRORS=true' \
  'UDA_MACHINE_ID=dba7dab19c316577a39b83040d8fc4c8723bddca5411087fded64717016cbe9f' \
  'NVM_BIN=/big_disk/dev-tools/nvm/versions/node/v22.23.0/bin' \
  'UDA_CLIENT=vscode' \
  'ELECTRON_RUN_AS_NODE=1' \
  'SHLVL=5' \
  'UVMC_HOME=/big_disk/uv-tools/UVMC_2026.06.P2.Beta' \
  'UDA_APP_VERSION=0.0.0-dev.f53bba8b' \
  'VSCODE_AGENT_FOLDER=/home/qlzheng/.vscode-server' \
  'UDA_DISABLE_CHANNEL_DB=true' \
  'UVH_HOME=/big_disk/uv-tools/UVH_2025.06.P4' \
  'LOGNAME=qlzheng' \
  'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/8903/bus' \
  'XDG_RUNTIME_DIR=/run/user/8903' \
  'PATH=/home/qlzheng/.vscode-server/extensions/univista.univista-design-agent-0.0.0-dev.f53bba8b/bin:/home/qlzheng/.vscode-server/cli/servers/Stable-4fe60c8b1cdac1c4c174f2fb180d0d758272d713/server/bin/remote-cli:/big_disk/uv-tools/UVMC_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVS_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVD_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVH_2025.06.P4/bin:/big_disk/uv-tools/UVEC_2025.06.P5/bin:/big_disk/uv-tools/vpslite/VPSlite_2025.09_20260527:/home/qlzheng/uda-linux-x64:/usr/local/zig-x86_64-linux-0.16.0:/big_disk/uv-tools/UVMC_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVS_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVD_2026.06.P2.Beta/bin:/big_disk/uv-tools/UVH_2025.06.P4/bin:/big_disk/uv-tools/UVEC_2025.06.P5/bin:/big_disk/uv-tools/vpslite/VPSlite_2025.09_20260527:/big_disk/dev-tools/miniconda3/bin:/big_disk/dev-tools/miniconda3/condabin:/big_disk/dev-tools/nvm/versions/node/v22.23.0/bin:/home/qlzheng/uda-linux-x64:/home/qlzheng/.local/bin:/home/qlzheng/bin:/usr/local/zig-x86_64-linux-0.16.0:/home/qlzheng/.local/npm/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/big_disk/dev-tools/go/go1.19.9/bin:/home/qlzheng/gopath/bin:/home/qlzheng/uda-linux-x64:/big_disk/dev-tools/go/go1.19.9/bin:/home/qlzheng/gopath/bin:/home/qlzheng/uda-linux-x64' \
  'UDA_VSCODE_VERSION=1.127.0' \
  'NODE_USE_SYSTEM_CA=1' \
  'DEBUGINFOD_URLS=https://debuginfod.centos.org/ ' \
  'CONDA_DEFAULT_ENV=base' \
  'NVM_INC=/big_disk/dev-tools/nvm/versions/node/v22.23.0/include/node' \
  'HISTSIZE=1000' \
  'VPS_HOME=/big_disk/uv-tools/vpslite/VPSlite_2025.09_20260527' \
  'UDACODE_EDITOR_NAME=Visual Studio Code 1.127.0' \
  'APPLICATION_INSIGHTS_NO_STATSBEAT=true' \
  'LESSOPEN=||/usr/bin/lesspipe.sh %s' \
  'UDA_ENABLE_QUESTION_TOOL=true' \
  'BASH_FUNC_which%%=() {  ( alias;
 eval ${which_declare} ) | /usr/bin/which --tty-only --read-alias --read-functions --show-tilde --show-dot $@
}' \
  "$__dump_invocation_exe" \
  '74' \
  '/big_disk/uv-tools/UVS_2026.06.P2.Beta/bin/uvlog2' \
  '-sv' \
  '-uvm1.2' \
  '-timescale' \
  '1ns/1ps' \
  '-define' \
  'SIMULATION' \
  '-define' \
  'UVM_NO_DEPRECATED' \
  '-include' \
  'rtl/cache' \
  '-include' \
  'rtl/common' \
  '-include' \
  'tb/uvm_tb/agents/axi_agent' \
  '-include' \
  'tb/uvm_tb/agents/ace_snoop_agent' \
  '-include' \
  'tb/uvm_tb/ref_model' \
  '-include' \
  'tb/uvm_tb/sequences' \
  '-include' \
  'tb/uvm_tb/scoreboard' \
  '-include' \
  'tb/uvm_tb/coverage' \
  '-include' \
  'tb/uvm_tb/env' \
  '-include' \
  'tb/uvm_tb/tests' \
  '-include' \
  'tb/assertions' \
  '-include' \
  'scripts/cdc' \
  'rtl/cache/l2_axi_master.sv' \
  'rtl/cache/l2_cache_pkg.sv' \
  'rtl/cache/l2_cache_top.sv' \
  'rtl/cache/l2_coherency_fsm.sv' \
  'rtl/cache/l2_data_array.sv' \
  'rtl/cache/l2_ecc_engine.sv' \
  'rtl/cache/l2_hit_miss_detect.sv' \
  'rtl/cache/l2_lru_controller.sv' \
  'rtl/cache/l2_mshr.sv' \
  'rtl/cache/l2_perf_counters.sv' \
  'rtl/cache/l2_prefetch_engine.sv' \
  'rtl/cache/l2_request_pipeline.sv' \
  'rtl/cache/l2_tag_array.sv' \
  'rtl/common/async_fifo.sv' \
  'rtl/common/rr_arbiter.sv' \
  'rtl/common/sync_fifo.sv' \
  'tb/uvm_tb/agents/axi_agent/axi_slave_agent.sv' \
  'tb/uvm_tb/agents/axi_agent/axi_master_agent.sv' \
  'tb/uvm_tb/agents/ace_snoop_agent/ace_snoop_agent.sv' \
  'tb/uvm_tb/sequences/l2_seq_items.sv' \
  'tb/uvm_tb/sequences/l2_coherency_seq.sv' \
  'tb/uvm_tb/ref_model/l2_ref_model.sv' \
  'tb/uvm_tb/scoreboard/l2_scoreboard.sv' \
  'tb/uvm_tb/coverage/l2_coverage.sv' \
  'tb/uvm_tb/env/l2_cache_env.sv' \
  'tb/uvm_tb/tests/l2_tests.sv' \
  'tb/uvm_tb/tests/l2_tests_extended.sv' \
  'tb/uvm_tb/tests/directed/l2_ecc_test.sv' \
  'tb/uvm_tb/tests/directed/l2_cdc_power_test.sv' \
  'tb/uvm_tb/tests/directed/l2_performance_test.sv' \
  'tb/assertions/l2_cache_assertions.sv' \
  'tb/top/l2_cache_tb_top.sv' \
  '-debug' \
  'all' \
  '-o' \
  '/tmp/uda-8903/tbchk/uvsim' \
  '-ddb' \
  '-icomp' \
  '-lsp_compile' \
  '-o' \
  '.uvsim.cache'

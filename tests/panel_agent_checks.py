"""Agent entry tests run with simulated commands and temporary filesystem paths."""
import os,subprocess,tempfile,unittest
from pathlib import Path
class PanelAgentEntryTests(unittest.TestCase):
 def bootstrap(self,release='https://github.com/Chen017/Xray-Panel/releases/tag/v9.8.7',resolve_status=0,download_status=0,bootstrap_status=0):
  source=(Path(__file__).resolve().parents[1]/'src/panel.sh').read_text()
  helpers=r'''
set -e
_fail(){ echo "$*"; }
command(){
 if [[ $1 == -v && $2 == xray-panel ]]; then return 1; fi
 builtin command "$@"
}
curl(){
 local target='' url=''
 printf 'curl:%s\n' "$*" >&2
 while (( $# )); do
  case "$1" in
   -o) target=$2; shift 2 ;;
   https://*) url=$1; shift ;;
   *) shift ;;
  esac
 done
 if [[ $url == https://github.com/Chen017/Xray-Panel/releases/latest ]]; then
  printf '%s' "$TEST_RELEASE"
  return "$TEST_RESOLVE_STATUS"
 fi
 [[ $target == */bootstrap.sh ]] || return 99
 # Even a partially downloaded file must never be executed on download failure.
 printf '#!/bin/bash\nprintf "bootstrap:%%s\\n" "$@"\nexit %s\n' "$TEST_BOOTSTRAP_STATUS" > "$target"
 return "$TEST_DOWNLOAD_STATUS"
}
rm(){
 local target=${!#}
 builtin command rm "$@"
 [[ ! -e $target ]] || return 99
 echo cleaned >&2
}
'''
  return subprocess.run(['bash'],input=helpers+source+'\npanel_agent_command install --version 9.8.7\n',text=True,capture_output=True,timeout=5,env={**os.environ,'TEST_RELEASE':release,'TEST_RESOLVE_STATUS':str(resolve_status),'TEST_DOWNLOAD_STATUS':str(download_status),'TEST_BOOTSTRAP_STATUS':str(bootstrap_status)})
 def test_missing_manager_resolves_published_release_and_forwards_arguments(self):
  p=self.bootstrap()
  self.assertEqual(p.returncode,0,p.stderr)
  self.assertIn('/v9.8.7/deploy/bootstrap.sh',p.stderr)
  self.assertIn("-w %{url_effective}",p.stderr)
  self.assertIn("--proto =https --proto-redir =https",p.stderr)
  self.assertEqual(p.stdout,'bootstrap:agent\nbootstrap:install\nbootstrap:--version\nbootstrap:9.8.7\n')
  self.assertIn('cleaned',p.stderr)
 def test_release_lookup_failure_stops_before_bootstrap_download(self):
  p=self.bootstrap(resolve_status=22)
  self.assertEqual(p.returncode,1,p.stderr)
  self.assertIn('无法获取 Panel 最新正式 Release',p.stdout)
  self.assertNotIn('raw.githubusercontent.com',p.stderr)
  self.assertNotIn('bootstrap:',p.stdout)
 def test_invalid_release_redirect_is_rejected_before_download(self):
  for release in ['https://github.com/Chen017/Xray-Panel/releases','https://github.com/Chen017/Xray-Panel/releases/tag/v9.8.7-rc1','https://example.com/releases/tag/v9.8.7','https://github.com/Chen017/Xray-Panel/releases/tag/v9.8.7/extra']:
   with self.subTest(release=release):
    p=self.bootstrap(release=release)
    self.assertEqual(p.returncode,1,p.stderr)
    self.assertIn('Release 地址无效',p.stdout)
    self.assertNotIn('raw.githubusercontent.com',p.stderr)
    self.assertNotIn('bootstrap:',p.stdout)
 def test_bootstrap_download_failure_reports_version_and_cleans_partial_file(self):
  p=self.bootstrap(download_status=22)
  self.assertEqual(p.returncode,1,p.stderr)
  self.assertIn('无法下载 Panel v9.8.7 管理器引导脚本',p.stdout)
  self.assertIn('/v9.8.7/deploy/bootstrap.sh',p.stdout)
  self.assertNotIn('bootstrap:',p.stdout)
  self.assertIn('cleaned',p.stderr)
 def test_bootstrap_failure_preserves_status_and_cleans_files(self):
  p=self.bootstrap(bootstrap_status=22)
  self.assertEqual(p.returncode,22,p.stderr)
  self.assertIn('Panel v9.8.7 管理器安装或 Agent 操作失败',p.stdout)
  self.assertIn('cleaned',p.stderr)
 def test_existing_legacy_agent_is_detected_before_manager_and_without_xray_mutations(self):
  repo=Path(__file__).resolve().parents[1]
  with tempfile.TemporaryDirectory(prefix='script-agent-test-') as tmp:
   root=Path(tmp);(root/'legacy/agent').mkdir(parents=True);(root/'legacy/agent/agent.py').touch();bin=root/'bin';bin.mkdir()
   manager=bin/'xray-panel';manager.write_text('#!/bin/bash\nprintf "manager:%s\\n" "$*"\n');manager.chmod(0o755)
   source=(repo/'src/panel.sh').read_text()
   for old,new in [('/opt/xray-panel-agent',(root/'new').as_posix()),('/opt/xray-panel',(root/'legacy').as_posix()),('/etc/xray-panel-agent',(root/'config').as_posix()),('/etc/systemd/system',(root/'units').as_posix())]:source=source.replace(old,new)
   script='''_info(){ echo "$*"; }; _fail(){ echo "$*"; }; systemctl(){ echo service-status; }; curl(){ echo unexpected-download; return 1; }
'''+source+'\npanel_agent_menu update\n'
   p=subprocess.run(['bash'],input=script,text=True,capture_output=True,env={**os.environ,'PATH':str(bin)+':'+os.environ['PATH']})
   self.assertEqual(p.returncode,0,p.stderr);self.assertIn('检测到本地 Agent',p.stdout);self.assertIn('manager:agent update',p.stdout);self.assertNotIn('unexpected-download',p.stdout)
 def test_direct_agent_branch_precedes_xray_dependencies_and_migration(self):
  source=(Path(__file__).resolve().parents[1]/'src/init.sh').read_text();entry=source.index('if [[ ${1:-} == agent ]]');self.assertLess(entry,source.index('\ncheck_dependencies\n'));self.assertLess(entry,source.index('load runtime.sh'))
 def menu(self,installed,answers,command='echo "manager:$*"'):
  source=(Path(__file__).resolve().parents[1]/'src/panel.sh').read_text()
  helpers='''clear(){ :; }; _line(){ echo LINE; }; _section(){ echo "$*"; }; _kv(){ echo "$*"; }; _menu(){ echo "$*"; }; _info(){ echo "$*"; }; _fail(){ echo "$*"; }; systemctl(){ return 0; }; pause(){ echo PAUSE; read -r ignored; }; prompt_confirm(){ return 0; }
'''
  script=helpers+source+f'\npanel_agent_installed(){{ return {0 if installed else 1}; }}\npanel_agent_present(){{ return 0; }}\npanel_agent_command(){{ {command}; }}\npanel_agent_menu <<\'ANS\'\n'+answers+'\nANS\n'
  p=subprocess.run(['bash'],input=script,text=True,capture_output=True,timeout=5);self.assertEqual(p.returncode,0,p.stderr);return p.stdout
 def test_installed_menu_hides_install_and_waits_after_each_action(self):
  text=self.menu(True,'1\n\n2\n\n3\n\n0')
  self.assertNotIn('安装 / 接入 Agent',text)
  self.assertRegex(text,r'manager:status\nPAUSE\s+LINE');self.assertRegex(text,r'manager:update\nPAUSE\s+LINE');self.assertRegex(text,r'manager:logs\nPAUSE\s+LINE')
 def test_uninstalled_menu_explains_retained_files_without_claiming_installed(self):
  text=self.menu(False,'1\n\n0');self.assertIn('未安装服务',text);self.assertIn('安装 / 接入 Agent',text);self.assertIn('manager:install\nPAUSE',text);self.assertNotIn('更新 / 修复 Agent',text)
 def test_failure_output_waits_and_uninstall_uses_safe_default(self):
  text=self.menu(True,'2\n\n4\n\n0',command='echo "manager:$*"; return 1')
  self.assertIn('manager:update\n操作未完成',text);self.assertEqual(text.count('PAUSE'),2);self.assertIn('manager:uninstall',text)
if __name__=='__main__':unittest.main()

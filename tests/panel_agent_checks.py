"""Agent entry tests run with simulated commands and temporary filesystem paths."""
import os,subprocess,tempfile,unittest
from pathlib import Path
class PanelAgentEntryTests(unittest.TestCase):
 def test_existing_legacy_agent_is_detected_before_manager_and_without_xray_mutations(self):
  repo=Path(__file__).resolve().parents[1]
  with tempfile.TemporaryDirectory(prefix='script-agent-test-') as tmp:
   root=Path(tmp);(root/'legacy/agent').mkdir(parents=True);(root/'legacy/agent/agent.py').touch();bin=root/'bin';bin.mkdir()
   manager=bin/'xray-panel';manager.write_text('#!/bin/bash\nprintf "manager:%s\\n" "$*"\n');manager.chmod(0o755)
   source=(repo/'src/panel.sh').read_text()
   for old,new in [('/opt/xray-panel-agent',str(root/'new')),('/opt/xray-panel',str(root/'legacy')),('/etc/xray-panel-agent',str(root/'config')),('/etc/systemd/system',str(root/'units'))]:source=source.replace(old,new)
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

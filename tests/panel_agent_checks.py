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
if __name__=='__main__':unittest.main()

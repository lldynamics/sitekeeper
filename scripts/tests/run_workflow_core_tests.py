#!/usr/bin/env python3
from pathlib import Path
import re,json,hashlib,argparse,tempfile,subprocess,sys,os
parser=argparse.ArgumentParser(description="Run Foundation business-core tests without using simulators or application data.")
parser.add_argument('--output', type=Path, help="New evidence directory; must not already exist")
parser.add_argument('--no-nested-sandbox', action='store_true', help="Disable only SwiftPM's nested sandbox when the outer managed environment rejects it")
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
if args.output:
 dest=args.output.resolve()
 dest.mkdir(parents=True,exist_ok=False)
else:
 dest=Path(tempfile.mkdtemp(prefix='sitekeeper-workflow-core-'))
src=dest/'Sources/sitekeeper';test=dest/'Tests/CoreTests'
src.mkdir(parents=True,exist_ok=True);test.mkdir(parents=True,exist_ok=True)
files=list((root/'Sources/Shared/Models').rglob('*.swift'))
files += [root/'Sources/Shared/Helpers'/name for name in ['DecimalFieldStorage.swift','DecimalValueObjects.swift','ExactDecimalCoefficient.swift','NumericInputSupport.swift','DataValueParser.swift','CodableEnumFallbacks.swift','BusinessDateValue.swift','Formatters.swift','AppPolicyAndBrand.swift']]
files += [root/name for name in ['Sources/Shared/Services/Finances/BusinessWorkflowStore.swift','Sources/Shared/Services/Finances/ProjectPaymentService.swift','Sources/Shared/Services/Projects/MaterialWarehouseWorkflow.swift','Sources/Shared/Services/Repository/RepositoryMaterialArithmetic.swift','Sources/Shared/Services/Backups/BackupSnapshot.swift','Sources/Shared/Services/Finances/ProjectPaymentMetrics.swift','Sources/Shared/Services/Finances/ProjectFinancialMetrics.swift','Sources/Shared/Services/Finances/BusinessWorkflowError.swift','Sources/Shared/Services/Persistence/DataStore/SnapshotSectionEncoder.swift','Sources/Shared/Helpers/RecordPage.swift']]
manifest={}
for index,p in enumerate(files):
 data=p.read_bytes()
 if p.name=='AppPolicyAndBrand.swift': data=data[:data.index(b'\nenum AppPolicy')]
 if p.name=='CommonMaterial.swift': data=data[:data.index(b'enum MaterialLibrary {')]
 (src/(str(index)+'_'+p.name)).write_bytes(data);manifest[str(p.relative_to(root))]={'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'compiled_sha256':hashlib.sha256(data).hexdigest(),'extracted_prefix':data!=p.read_bytes()}
# Exact model declarations extracted from iOS storage files. Device I/O is excluded.
blocks=[]
for name,token in [('Photos/PhotoStorage.swift','struct PhotoBackupFile:'),('Drawings/DrawingStorage.swift','struct DrawingBackupFile:'),('Documents/ProjectDocumentStorage.swift','struct ProjectDocumentBackupFile:'),('QuickNotes/QuickNoteAttachmentStorage.swift','struct QuickNoteAttachmentBackupFile:')]:
 p=root/'Sources/Shared/Services/Storage'/name;s=p.read_text();start=s.index(token);end=s.index('\n}',start)+2;blocks.append(s[start:end]);manifest[str(p.relative_to(root))]={'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'extracted':True}
p=root/'Sources/Shared/Services/Notifications/DueReminderPlanBuilder.swift';s=p.read_text();blocks.append(s[:s.index('extension DueReminderSnapshot')]);blocks.append(s[s.index('struct DueReminderPlan:'):]);manifest[str(p.relative_to(root))]={'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'extracted':True}
p=root/'Sources/Shared/Services/Drafts/BusinessDraftStore.swift';s=p.read_text();start=s.index('    static func fingerprint<');end=s.index('\n    }',start)+6;blocks.append('enum BusinessDraftStore {\n'+s[start:end]+'\n}')
p=root/'Sources/Features/Dashboard/DashboardCardViews.swift';s=p.read_text();start=s.index('enum DashboardSubtitleBuilder');end=s.index('\n}',start)+2;blocks.append(s[start:end])
p=root/'Sources/Shared/Services/Backups/BackupArchiveRestoreJournal.swift';s=p.read_text();start=s.index('    static func encodeMetadata(');end=s.index('\n    }',start)+6;blocks.append('enum BackupArchiveRestoreJournal {\n'+s[start:end]+'\n}')
for relative in ['Sources/Shared/Services/Drafts/BusinessDraftStore.swift','Sources/Features/Dashboard/DashboardCardViews.swift','Sources/Shared/Services/Backups/BackupArchiveRestoreJournal.swift']:
 manifest[relative]={'source_sha256':hashlib.sha256((root/relative).read_bytes()).hexdigest(),'extracted':True}
(src/'PortableBoundarySupport.swift').write_text('import Foundation\n\n'+'\n\n'.join(blocks)+'''\n
// Display adapters only; localization, UIKit, DataStore and disk transactions
// are deliberately outside this host harness's acceptance scope.
enum AppLocalization { static func string(_ key: String.LocalizationValue) -> String { String(localized: key) } }
enum ReportBuilder { static func money(_ value: MoneyValue) -> String { value.wireText } }
''')
for name in ['BusinessWorkflowOptimizationTests.swift','LargeDataOptimizationTests.swift','BusinessWorkflowServiceTests.swift']:
 s=(root/'Tests'/name).read_text()
 s=re.sub(r'^    @MainActor private func temporaryStore.*?(?=^    private func plan)', '', s, flags=re.S|re.M)
 s=re.sub(r'^    @MainActor @Test.*?(?=^    @(?:MainActor|Test)|^})', '', s, flags=re.S|re.M)
 s=re.sub(r'^    @Test func (?:preparedRestoreInvalidates|failedAtomicWrite).*?(?=^    @Test|^})','',s,flags=re.S|re.M)
 (test/name).write_text(s)
(dest/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SitekeeperCoreValidation", platforms: [.macOS(.v14)], targets: [.target(name: "sitekeeper"), .testTarget(name: "CoreTests", dependencies: ["sitekeeper"])], swiftLanguageModes: [.v5])
''')
(dest/'source-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
expected=sum(p.read_text().count('@Test func') for p in test.glob('*.swift'))
print('Portable core cases:',expected,flush=True)
print('Boundary: localization/amount display adapters only; native DataStore, disk restore transactions and UI are excluded.',flush=True)
log=dest/'test.log'
with log.open('w') as output:
 environment=os.environ.copy()
 environment['CLANG_MODULE_CACHE_PATH']=str(dest/'module-cache')
 environment['SWIFT_MODULECACHE_PATH']=str(dest/'module-cache')
 command=['swift','test','--package-path',str(dest),'--cache-path',str(dest/'cache'),
          '--config-path',str(dest/'config'),'--security-path',str(dest/'security')]
 if args.no_nested_sandbox: command.append('--disable-sandbox')
 result=subprocess.run(command,cwd=dest,env=environment,stdout=output,stderr=subprocess.STDOUT)
text=log.read_text()
match=re.search(r'Test run with (\d+) tests? in .* passed',text)
passed=int(match.group(1)) if match else 0
summary={'expected':expected,'passed':passed,'returncode':result.returncode,'success':result.returncode==0 and passed==expected and expected>0,'scope':'Foundation core and services with an injected store; native persistence and UI excluded'}
(dest/'summary.json').write_text(json.dumps(summary,indent=2))
print(json.dumps(summary),flush=True)
print('Evidence:',dest,flush=True)
sys.exit(0 if summary['success'] else 1)

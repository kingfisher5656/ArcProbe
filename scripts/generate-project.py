#!/usr/bin/env python3
"""Regenerate the native Xcode project without external tooling."""
from pathlib import Path
import hashlib, json
root = Path(__file__).resolve().parents[1]
project = root / 'ArcaeaOffline.xcodeproj'
project.mkdir(exist_ok=True)
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(value): return json.dumps(str(value))
objects = []
def obj(name, content):
    key = uid(name); objects.append(f'{key} = {{ {content} }};'); return key
files = {}
for folder in ['ArcaeaOffline', 'ArcaeaOfflineTests', 'ArcaeaOfflineUITests']:
    for file in sorted((root / folder).rglob('*.swift')):
        rel = str(file.relative_to(root))
        files[rel] = obj('file:'+rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
assets = obj('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = ArcaeaOffline/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;')
products=[]; target_ids=[]; config_ids={}
for target, ext in [('ArcaeaOffline','app'),('ArcaeaOfflineTests','xctest'),('ArcaeaOfflineUITests','xctest')]:
    product=obj('product:'+target, f'isa = PBXFileReference; explicitFileType = {"wrapper.application" if ext == "app" else "wrapper.cfbundle"}; includeInIndex = 0; path = {q(target+"."+ext)}; sourceTree = BUILT_PRODUCTS_DIR;'); products.append(product)
    sourcebuild=[]
    for path, file in files.items():
        if path.split('/')[0] == target: sourcebuild.append(obj('build:'+path, f'isa = PBXBuildFile; fileRef = {file};'))
    sources=obj('sources:'+target, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(sourcebuild)}); runOnlyForDeploymentPostprocessing = 0;')
    resources=[]
    if target == 'ArcaeaOffline': resources=[obj('assetbuild',f'isa = PBXBuildFile; fileRef = {assets};')]
    resourcephase=obj('resources:'+target, f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resources)}); runOnlyForDeploymentPostprocessing = 0;')
    frameworks=[]; deps=[]
    if target != 'ArcaeaOfflineUITests':
        for pkg in ['ArcaeaCore']:
            dep=obj('pkgdep:'+target+pkg, f'isa = XCSwiftPackageProductDependency; package = {uid("pkgref:"+pkg)}; productName = {pkg};'); deps.append(dep)
            frameworks.append(obj('pkgbuild:'+target+pkg,f'isa = PBXBuildFile; productRef = {dep};'))
    fw=obj('frameworks:'+target,f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({",".join(frameworks)}); runOnlyForDeploymentPostprocessing = 0;')
    configs=[]
    for configuration in ['Debug','Release']:
        settings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'app.arcaeaoffline'+('.tests' if target.endswith('Tests') and not target.endswith('UITests') else '.uitests' if target.endswith('UITests') else ''),'IPHONEOS_DEPLOYMENT_TARGET':'18.0','TARGETED_DEVICE_FAMILY':'1,2','GENERATE_INFOPLIST_FILE':'YES','SWIFT_VERSION':'6.0','CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'2','MARKETING_VERSION':'0.2.0','SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SWIFT_STRICT_CONCURRENCY':'complete'}
        if target == 'ArcaeaOffline':
            settings.update({'INFOPLIST_KEY_CFBundleDisplayName':'ArcProbe','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight','INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad':'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ENABLE_PREVIEWS':'YES'})
        elif target == 'ArcaeaOfflineTests':
            settings.update({'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/ArcaeaOffline.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ArcaeaOffline','BUNDLE_LOADER':'$(TEST_HOST)'})
        else: settings['TEST_TARGET_NAME']='ArcaeaOffline'
        if configuration == 'Debug': settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG','ONLY_ACTIVE_ARCH':'YES','ENABLE_TESTABILITY':'YES'})
        configs.append(obj('config:'+target+configuration,'isa = XCBuildConfiguration; buildSettings = {'+' '.join(f'{k} = {q(v)};' for k,v in settings.items())+f'}}; name = {configuration};'))
    configlist=obj('configlist:'+target,f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    dependencies=[]
    if target != 'ArcaeaOffline':
        proxy=obj('proxy:'+target,f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target:ArcaeaOffline")}; remoteInfo = ArcaeaOffline;')
        dependencies.append(obj('targetdependency:'+target,f'isa = PBXTargetDependency; target = {uid("target:ArcaeaOffline")}; targetProxy = {proxy};'))
    tid=obj('target:'+target,f'isa = PBXNativeTarget; buildConfigurationList = {configlist}; buildPhases = ({sources},{fw},{resourcephase}); buildRules = (); dependencies = ({",".join(dependencies)}); name = {target}; packageProductDependencies = ({",".join(deps)}); productName = {target}; productReference = {product}; productType = {q("com.apple.product-type.application" if ext=="app" else "com.apple.product-type.bundle.ui-testing" if target.endswith("UITests") else "com.apple.product-type.bundle.unit-test")};'); target_ids.append(tid)
productgroup=obj('products',f'isa = PBXGroup; children = ({",".join(products)}); name = Products; sourceTree = "<group>";')
main=obj('main',f'isa = PBXGroup; children = ({",".join(files.values())},{assets},{productgroup}); sourceTree = "<group>";')
projectconfigs=[]
for c in ['Debug','Release']:
    projectconfigs.append(obj('projconfig:'+c,f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; GCC_C_LANGUAGE_STANDARD = gnu17; }}; name = {c};'))
plist=obj('projconfiglist',f'isa = XCConfigurationList; buildConfigurations = ({",".join(projectconfigs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
packages=[]
for p in ['ArcaeaCore']: packages.append(obj('pkgref:'+p,f'isa = XCLocalSwiftPackageReference; relativePath = Packages/{p};'))
obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; TargetAttributes = {{ {uid("target:ArcaeaOfflineTests")} = {{ TestTargetID = {uid("target:ArcaeaOffline")}; }}; {uid("target:ArcaeaOfflineUITests")} = {{ TestTargetID = {uid("target:ArcaeaOffline")}; }}; }}; }}; buildConfigurationList = {plist}; compatibilityVersion = "Xcode 15.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main}; productRefGroup = {productgroup}; projectDirPath = ""; projectRoot = ""; packageReferences = ({",".join(packages)}); targets = ({",".join(target_ids)});')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+uid('project')+'; }\n')
scheme=project/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
def ref(t): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:"+t)}" BuildableName="{t}.{ "app" if t == "ArcaeaOffline" else "xctest"}" BlueprintName="{t}" ReferencedContainer="container:ArcaeaOffline.xcodeproj"/>'
(scheme/'ArcaeaOffline.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref('ArcaeaOffline')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref('ArcaeaOfflineTests')}</TestableReference><TestableReference skipped="NO">{ref('ArcaeaOfflineUITests')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('ArcaeaOffline')}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref('ArcaeaOffline')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(f'Generated project with {len(files)} Swift files')

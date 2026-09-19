#!/usr/bin/env python3
"""Generate the dependency-free Xcode project. Run from any directory."""
import hashlib
import json
import pathlib
import plistlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Nultra.xcodeproj"
PROJECT.mkdir(exist_ok=True)
objects = {}

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def obj(key_name, isa, **values):
    key = uid(key_name)
    objects[key] = {"isa": isa, **values}
    return key

files = []
builds = []
for source in sorted((ROOT / "Nultra").rglob("*.swift")):
    path = source.relative_to(ROOT).as_posix()
    ref = obj(path, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=path, sourceTree="SOURCE_ROOT")
    files.append(ref)
    builds.append(obj(path + "-build", "PBXBuildFile", fileRef=ref))
assets = obj("assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path="Nultra/Assets.xcassets", sourceTree="SOURCE_ROOT")
files.append(assets)
resources = obj("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647,
                files=[obj("assets-build", "PBXBuildFile", fileRef=assets)], runOnlyForDeploymentPostprocessing=0)
sources = obj("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
frameworks = obj("frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
product = obj("product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="Nultra.app", sourceTree="BUILT_PRODUCTS_DIR")
products = obj("products", "PBXGroup", children=[product], name="Products", sourceTree="<group>")
main = obj("main-group", "PBXGroup", children=files + [products], sourceTree="<group>")

project_configs = []
target_configs = []
for name in ["Debug", "Release"]:
    project_configs.append(obj("project-" + name, "XCBuildConfiguration", name=name, buildSettings={
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "SDKROOT": "iphoneos",
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0", "SWIFT_VERSION": "5.0",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
        "ENABLE_TESTABILITY": "YES" if name == "Debug" else "NO",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if name == "Debug" else "",
    }))
    target_configs.append(obj("target-" + name, "XCBuildConfiguration", name=name, buildSettings={
        "PRODUCT_BUNDLE_IDENTIFIER": "com.afshinki.nultra", "PRODUCT_NAME": "$(TARGET_NAME)",
        "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "Nultra/Info.plist",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "TARGETED_DEVICE_FAMILY": "1",
        "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "6", "MARKETING_VERSION": "0.6.0",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    }))
pc = obj("project-configs", "XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
tc = obj("target-configs", "XCConfigurationList", buildConfigurations=target_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
target = obj("target", "PBXNativeTarget", buildConfigurationList=tc, buildPhases=[sources, frameworks, resources],
             buildRules=[], dependencies=[], name="Nultra", productName="Nultra", productReference=product, productType="com.apple.product-type.application")
# UI regression target, deliberately separate from the Foundation-only Swift package.
ui_source = obj("ui-source", "PBXFileReference", lastKnownFileType="sourcecode.swift", path="UITests/NultraUITests.swift", sourceTree="SOURCE_ROOT")
objects[main]["children"].append(ui_source)
ui_product = obj("ui-product", "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path="NultraUITests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
objects[products]["children"].append(ui_product)
ui_sources = obj("ui-sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=[obj("ui-source-build", "PBXBuildFile", fileRef=ui_source)], runOnlyForDeploymentPostprocessing=0)
ui_configs = []
for name in ["Debug", "Release"]:
    ui_configs.append(obj("ui-" + name, "XCBuildConfiguration", name=name, buildSettings={
        "PRODUCT_BUNDLE_IDENTIFIER": "com.afshinki.nultra.uitests", "PRODUCT_NAME": "$(TARGET_NAME)",
        "GENERATE_INFOPLIST_FILE": "YES", "TARGETED_DEVICE_FAMILY": "1", "CODE_SIGN_STYLE": "Automatic",
        "TEST_TARGET_NAME": "Nultra", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
    }))
ui_config_list = obj("ui-config-list", "XCConfigurationList", buildConfigurations=ui_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
proxy = obj("ui-proxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1, remoteGlobalIDString=target, remoteInfo="Nultra")
dependency = obj("ui-dependency", "PBXTargetDependency", target=target, targetProxy=proxy)
ui_target = obj("ui-target", "PBXNativeTarget", buildConfigurationList=ui_config_list, buildPhases=[ui_sources], buildRules=[], dependencies=[dependency], name="NultraUITests", productName="NultraUITests", productReference=ui_product, productType="com.apple.product-type.bundle.ui-testing")
project = obj("project", "PBXProject", attributes={"LastUpgradeCheck": "1420", "TargetAttributes": {target: {"CreatedOnToolsVersion": "14.2"}}},
              buildConfigurationList=pc, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0,
              knownRegions=["en", "Base"], mainGroup=main, productRefGroup=products, projectDirPath="", projectRoot="", targets=[target, ui_target])

# OpenStep serialization (the native pbxproj format); quote all scalar strings.
def encode(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, dict):
        return "{\n" + "".join(pad + "\t" + json.dumps(str(k)) + " = " + encode(v, indent + 1) + ";\n" for k, v in value.items()) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join(pad + "\t" + encode(v, indent + 1) + ",\n" for v in value) + pad + ")"
    return str(value) if isinstance(value, int) else json.dumps(value)

(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}) + "\n")
schemes = PROJECT / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Nultra.app" BlueprintName="Nultra" ReferencedContainer="container:Nultra.xcodeproj"/>'
ui_reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="NultraUITests.xctest" BlueprintName="NultraUITests" ReferencedContainer="container:Nultra.xcodeproj"/>'
(schemes / "Nultra.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1420" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{ui_reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ui_reference}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
info = {
    "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)", "CFBundleDisplayName": "Nultra",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "$(PRODUCT_NAME)", "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "LSRequiresIPhoneOS": True, "NSBluetoothAlwaysUsageDescription": "Nultra uses Bluetooth to find and control your nearby switches directly from your iPhone.",
    "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
    "UILaunchScreen": {}, "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
}
with (ROOT / "Nultra/Info.plist").open("wb") as file:
    plistlib.dump(info, file)
print("Generated Nultra.xcodeproj and Info.plist")

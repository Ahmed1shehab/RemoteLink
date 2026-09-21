#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the RemoteLinkWatch watchOS app to Runner.xcodeproj, and embeds it in the
# iPhone app so it installs alongside.
#
# Why a script rather than a checked-in project file: `project.pbxproj` is a
# 700-line generated document that Flutter, CocoaPods and Xcode all rewrite, and
# a hand-merged watch target in it is the kind of change that survives exactly
# until the next `pod install`. Expressing it as a script means the change can
# be re-applied, reviewed as fifty lines instead of five hundred, and — because
# it is idempotent — run again after any tool has been through the file.
#
#   cd apps/mobile/ios && ruby tool/add_watch_target.rb
#
# Requires the `xcodeproj` gem, which ships with CocoaPods. Safe to run twice:
# it reports and exits if the target is already there.

require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'Runner.xcodeproj')
SOURCE_DIR = File.join(ROOT, 'RemoteLinkWatch')

TARGET_NAME = 'RemoteLinkWatch'
BUNDLE_ID = 'com.remotelink.app.watchkitapp'
COMPANION_ID = 'com.remotelink.app'
DEPLOYMENT_TARGET = '10.0'
DEVELOPMENT_TEAM = 'J672UY5K99'

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found — is this the Flutter iOS project?' if runner.nil?

# The iPhone side of the link. Added to Runner rather than to the watch target:
# it is the `WCSessionDelegate` running in the phone app, and it is what hands
# what the wrist did to Dart. Guarded separately from the watch target below, so
# a project that has one but not the other is repaired rather than skipped.
runner_group = project.main_group['Runner'] || project.main_group
bridge_name = 'WatchBridge.swift'
already_in_runner = runner.source_build_phase.files_references.any? do |ref|
  ref.respond_to?(:path) && File.basename(ref.path.to_s) == bridge_name
end
unless already_in_runner
  existing = runner_group.files.find { |f| File.basename(f.path.to_s) == bridge_name }
  reference = existing || runner_group.new_reference(bridge_name)
  runner.add_file_references([reference])
  puts "Added #{bridge_name} to Runner."
end

if project.targets.any? { |t| t.name == TARGET_NAME }
  puts "#{TARGET_NAME} is already in the project."
  project.save
  exit 0
end

watch = project.new_target(
  :application,
  TARGET_NAME,
  :watchos,
  DEPLOYMENT_TARGET,
  nil,
  :swift
)

# A group that points at the real directory, so files added to
# ios/RemoteLinkWatch later show up where they live rather than at the root.
group = project.main_group.new_group(TARGET_NAME, 'RemoteLinkWatch')

Dir.glob(File.join(SOURCE_DIR, '*.swift')).sort.each do |path|
  reference = group.new_reference(File.basename(path))
  watch.add_file_references([reference])
end

assets = group.new_reference('Assets.xcassets')
watch.add_resources([assets])

watch.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['INFOPLIST_FILE'] = 'RemoteLinkWatch/Info.plist'
  # `NO`, because the Info.plist above is written by hand and holds the two keys
  # that make this a watch app at all. With generation on, Xcode writes its own
  # and the companion identifier is silently dropped.
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['WATCHOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['SDKROOT'] = 'watchos'
  settings['TARGETED_DEVICE_FAMILY'] = '4'
  settings['SUPPORTED_PLATFORMS'] = 'watchos watchsimulator'
  settings['SWIFT_VERSION'] = '5.0'
  settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  settings['DEVELOPMENT_TEAM'] = DEVELOPMENT_TEAM
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['SKIP_INSTALL'] = 'NO'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['MARKETING_VERSION'] = '1.0'
  settings['ENABLE_PREVIEWS'] = 'YES'
  # The watch app is a leaf: it links nothing but system frameworks, and it must
  # not inherit the Pods search paths the Runner configuration sets for iOS.
  settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks'
end

# The iPhone app carries the watch app inside it. Without this phase the watch
# app builds and is never installed on anything.
embed = runner.new_copy_files_build_phase('Embed Watch Content')
embed.symbol_dst_subfolder_spec = :products_directory
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
build_file = embed.add_file_reference(watch.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Before Flutter's "Thin Binary", not after it. Appended at the end — where
# `new_copy_files_build_phase` puts it — the phase writes into `Runner.app`
# after a script phase that has already declared the same bundle as its output,
# and Xcode refuses the whole build with "Cycle inside Runner". Slotted ahead of
# every run-script phase, the watch app is in place before anything inspects the
# bundle, which is also the order Xcode itself uses when it adds this phase.
runner.build_phases.delete(embed)
first_script = runner.build_phases.index do |phase|
  phase.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) &&
    phase.name.to_s.include?('Thin Binary')
end
runner.build_phases.insert(first_script || runner.build_phases.count, embed)

# So building Runner builds the watch app first, rather than embedding whatever
# happens to be left in the products directory from a previous build.
runner.add_dependency(watch)

# Xcode's "Signing & Capabilities" pane does not read the build settings above.
# It reads `TargetAttributes`, and a target created outside Xcode has no entry
# there at all — so the pane shows the team as unset, never asks the portal for
# a profile, and every build silently falls back to whatever profile happens to
# be cached. That is how a watch app ends up signed with an *iOS* team profile
# that cannot be installed on a watch.
project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][watch.uuid] = {
  'CreatedOnToolsVersion' => '26.0',
  'ProvisioningStyle' => 'Automatic',
  'DevelopmentTeam' => DEVELOPMENT_TEAM,
}

# A shared scheme, so the watch app can be run straight onto a paired watch
# from Xcode's destination menu or from `xcodebuild -scheme RemoteLinkWatch`.
# Xcode would autocreate one on first open, but only in the local user's
# `xcuserdata` — which is not committed, so every developer would have to
# rediscover it, and CI would have no scheme at all.
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(watch)
scheme.set_launch_target(watch)
scheme.save_as(PROJECT_PATH, TARGET_NAME, true)

project.save
puts "Added #{TARGET_NAME} (#{BUNDLE_ID}) and embedded it in Runner."

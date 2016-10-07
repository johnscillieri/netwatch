# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]
### Added
- A real license, GPLv3
- Check for UPX in build and warn if not found

### Changed
- Now hosted on github
- Ported to Nim v0.15.0
- Removed config.nims, all build info is now in the makefile

### Fixed
- Cleaned up code in netwatch.main
- Issue with footer display when shrinking window really small
- Missing bin directory on first build

## [0.9.0] - 2016-10-01
### Added
- Stripping & UPX packing for release builds
- Lots more information in the README

### Fixed
- Flickering of table during high-speed scans. Now only redraws the table if it
hasn't changed
- Appending to an existing label doesn't auto-erase
- Terminal now redraws on height change

## [0.8.0] - 2016-09-30
### Added
- Label mappings are now saved back to the ini file on close
- The last used network is now stored in the ini file as the default

### Changed
- Default ini file path is now ~/.config/netwatch.ini

### Fixed
- Couldn't change the name of the last entry
- Typing numbers didn't work when changing labels once the user began typing

## [0.7.0] - 2016-09-29
### Added
- Support for changing labels via the U/I. They're not currently saved on exit (coming in 0.8)

### Changed
- Last seen resolution now groups 0-59s as <1m

### Fixed
- Don't need to run as super user to see the help.

## [0.6.0] - 2016-09-27
### Added
- First tagged revision

### Changed
- In active mode the table redraws only when a packet comes in or the user presses a key. Should keep the CPU at 0 most of the time.

[Unreleased]: https://dev.visionistinc.com/gitlab/jfscillieri/netwatch/compare/v0.9.0...HEAD
[0.9.0]: https://dev.visionistinc.com/gitlab/jfscillieri/netwatch/compare/v0.8.0...v0.9.0
[0.8.0]: https://dev.visionistinc.com/gitlab/jfscillieri/netwatch/compare/v0.7.0...v0.8.0
[0.7.0]: https://dev.visionistinc.com/gitlab/jfscillieri/netwatch/compare/v0.6.0...v0.7.0
[0.6.0]: https://dev.visionistinc.com/gitlab/jfscillieri/netwatch/compare/beea00ec...v0.6.0

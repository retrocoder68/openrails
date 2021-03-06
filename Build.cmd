@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

ECHO  ##############################################################################
ECHO  #         ___                             ____            _   _              #
ECHO  #        / _ \   _ __     ___   _ __     ^|  _ \    __ _  (_) ^| ^|  ___        #
ECHO  #       ^| ^| ^| ^| ^| '_ \   / _ \ ^| '_ \    ^| ^|_) ^|  / _` ^| ^| ^| ^| ^| / __^|       #
ECHO  #       ^| ^|_^| ^| ^| ^|_) ^| ^|  __/ ^| ^| ^| ^|   ^|  _ ^<  ^| (_^| ^| ^| ^| ^| ^| \__ \       #
ECHO  #        \___/  ^| .__/   \___^| ^|_^| ^|_^|   ^|_^| \_\  \__,_^| ^|_^| ^|_^| ^|___/       #
ECHO  #               ^|_^|                                                          #
ECHO  ##############################################################################
ECHO.
ECHO This script will build Open Rails. Syntax:
ECHO.
ECHO %0 MODE
ECHO.
ECHO   MODE          Selects the mode to build with:
ECHO     unstable      Doesn't include documentation or installers
ECHO     testing       Includes documentation but not installers
ECHO     stable        Includes documentation and installers
ECHO.

REM Check for necessary tools.
ECHO The following tools must be available in %%PATH%% for the build to work:
ECHO [UTS] indicates which build modes need the tool: unstable, testing, and stable.
SET CheckToolInPath.Missing=0
SET CheckToolInPath.Check=0
:check-tools
CALL :list-or-check-tool "svn.exe" "[UTS] Subversion tool"
CALL :list-or-check-tool "nuget.exe" "[UTS] .NET package manager tool"
CALL :list-or-check-tool "MSBuild.exe" "[UTS] Microsoft Visual Studio build tool"
CALL :list-or-check-tool "lazbuild.exe" "[UTS] Lazarus compiler"
CALL :list-or-check-tool "strip.exe" "[UTS] Lazarus tool"
CALL :list-or-check-tool "xunit.console.x86.exe" "[UTS] XUnit tool"
CALL :list-or-check-tool "editbin.exe" "[UTS] Microsoft Visual Studio editbin tool"
CALL :list-or-check-tool "rcedit-x86.exe" "[UTS] Electron rcedit tool"
CALL :list-or-check-tool "7za.exe" "[UTS] 7-zip tool"
CALL :list-or-check-tool "OfficeToPDF.exe" "[TS] Office-to-PDF conversion tool"
CALL :list-or-check-tool "iscc.exe" "[S] Inno Setup 5 compiler"
IF "%CheckToolInPath.Check%" == "0" (
	ECHO.
	SET CheckToolInPath.Check=1
	GOTO :check-tools
)

REM Parse command line
SET Mode=-
SET Flag.Changelog=0
SET Flag.Updater=0
:parse-command-line
IF /I "%~1" == "unstable" SET Mode=Unstable
IF /I "%~1" == "testing"  SET Mode=Testing
IF /I "%~1" == "stable"   SET Mode=Stable
SHIFT /1
IF NOT "%~1" == "" GOTO :parse-command-line
IF "%Mode%" == "-" (
	>&2 ECHO ERROR: No build mode specified.
	ECHO Run "Build.cmd MODE" where MODE is "unstable", "testing" or "stable".
	EXIT /B 1
)
IF %CheckToolInPath.Missing% GTR 0 (
	TIMEOUT /T 10
)

REM Check for necessary directory.
IF NOT EXIST "Source\ORTS.sln" (
	>&2 ECHO ERROR: Unexpected current directory.
	ECHO Run "Build.cmd" in the parent directory of "ORTS.sln" ^(the directory "Build.cmd" is in^).
	EXIT /B 1
)

IF "%Mode%" == "Stable" (
	CALL :create "Microsoft .NET Framework Redistributable 3.5 SP1"
	CALL :create "Microsoft .NET Framework Redistributable 3.5 SP1 download manager"
	CALL :create "Microsoft XNA Framework Redistributable 3.1"
	IF NOT EXIST "Microsoft .NET Framework Redistributable 3.5 SP1\dotnetfx35.exe" (
		>&2 ECHO ERROR: Missing required file for "%Mode%" build: "Microsoft .NET Framework Redistributable 3.5 SP1\dotnetfx35.exe".
		EXIT /B 1
	)
	IF NOT EXIST "Microsoft .NET Framework Redistributable 3.5 SP1 download manager\dotnetfx35setup.exe" (
		>&2 ECHO ERROR: Missing required file for "%Mode%" build: "Microsoft .NET Framework Redistributable 3.5 SP1 download manager\dotnetfx35setup.exe".
		EXIT /B 1
	)
	IF NOT EXIST "Microsoft XNA Framework Redistributable 3.1\xnafx31_redist.msi" (
		>&2 ECHO ERROR: Missing required file for "%Mode%" build: "Microsoft XNA Framework Redistributable 3.1\xnafx31_redist.msi".
		EXIT /B 1
	)
)

REM Get code revision.
SET Revision=000
IF EXIST ".svn" (
	FOR /F "usebackq tokens=1" %%R IN (`svn --non-interactive info --show-item revision .`) DO SET Revision=%%R
)
IF EXIST ".git" (
	FOR /F "usebackq tokens=1" %%R IN (`git describe --first-parent --always`) DO SET Revision=%%R
)
IF "%Revision%" == "000" (
	>&2 ECHO WARNING: No Subversion or Git revision found.
)

REM Restore NuGet packages.
nuget restore Source\ORTS.sln || GOTO :error

REM Recreate Program directory for output.
CALL :recreate "Program" || GOTO :error

REM Build main program.
REM Disable warning CS1591 "Missing XML comment for publicly visible type or member".
MSBuild Source\ORTS.sln /t:Clean;Build /p:Configuration=Release /p:NoWarn=1591 || GOTO :error

REM Build contributed Timetable Editor.
PUSHD Source\Contrib\TimetableEditor && CALL Build.cmd && POPD || GOTO :error

REM Set update channel.
>>Program\Updater.ini ECHO Channel=string:%Mode% || GOTO :error
ECHO Set update channel to "%Mode%".

REM Set version number.
IF NOT "%Version%" == "" (
	>Program\Version.txt ECHO %Version%. || GOTO :error
	ECHO Set version number to "%Version%".
) ELSE (
	>Program\Version.txt ECHO X || GOTO :error
	ECHO Set version number to none.
)

REM Set revision number.
>Program\Revision.txt ECHO $Revision: %Revision% $ || GOTO :error
ECHO Set revision number to "%Revision%".

REM Build locales.
PUSHD Source\Locales && CALL Update.bat non-interactive && POPD || GOTO :error

REM Run unit tests (9009 means XUnit itself wasn't found, which is an error).
xunit.console.x86 Program\Tests.dll /nunit xunit.xml
IF "%ERRORLEVEL%" == "9009" GOTO :error

CALL :copy "Program\RunActivity.exe" "Program\RunActivityLAA.exe" || GOTO :error
editbin /NOLOGO /LARGEADDRESSAWARE "Program\RunActivityLAA.exe" || GOTO :error
copy "Program\RunActivity.exe.config" "Program\RunActivityLAA.exe.config" || GOTO :error
ECHO Created large address aware version of RunActivity.exe.

REM Copy the Web content, empty the destination folder first
IF EXIST "Program\Content\Web" RMDIR "Program\Content\Web" /S /Q
IF NOT EXIST "Program\Content\Web" MKDIR "Program\Content\Web"
XCOPY "Source\RunActivity\Viewer3D\WebServices\Web" "Program\Content\Web" /S /Y || GOTO :error

REM Copy version number from OpenRails.exe into all other 1st party files
SET VersionInfoVersion=0.0.0.0
IF NOT "%Version%" == "" (
	SET VersionInfoVersion=%Version%.%Revision%
) ELSE (
	FOR /F "usebackq tokens=1" %%V IN (`rcedit-x86.exe "Program\OpenRails.exe" --get-version-string FileVersion`) DO SET VersionInfoVersion=%%V
)
IF "%VersionInfoVersion%" == "0.0.0.0" (
	>&2 ECHO ERROR: No VersionInfoVersion found in "Program\OpenRails.exe".
	GOTO :error
)
FOR %%F IN ("Program\*.exe", "Program\Orts.*.dll", "Program\Contrib.*.dll", "Program\Tests.dll") DO (
	rcedit-x86.exe "%%~F" --set-product-version %VersionInfoVersion% --set-file-version %VersionInfoVersion% --set-version-string ProductVersion %VersionInfoVersion% --set-version-string FileVersion %VersionInfoVersion% || GOTO :error
)
ECHO Set product and file version information to "%VersionInfoVersion%".

REM *** Special build step: signs binaries ***
IF NOT "%JENKINS_TOOLS%" == "" (
	FOR /R "Program" %%F IN (*.exe *.dll) DO CALL "%JENKINS_TOOLS%\sign.cmd" "%%~F" || GOTO :error
)

IF NOT "%Mode%" == "Unstable" (
	REM Restart the Office Click2Run service as this frequently breaks builds.
	NET stop ClickToRunSvc
	NET start ClickToRunSvc

	REM Recreate Documentation folder for output.
	CALL :recreate "Program\Documentation" || GOTO :error

	REM Compile the documentation.
	FOR /R "Source\Documentation" %%F IN (*.doc *.docx *.docm *.xls *.xlsx *.xlsm *.odt) DO ECHO %%~F && OfficeToPDF.exe /bookmarks /print "%%~F" "Program\Documentation\%%~nF.pdf" || GOTO :error
	PUSHD "Source\Documentation\Manual" && CALL make.bat clean & POPD || GOTO :error
	PUSHD "Source\Documentation\Manual" && CALL make.bat latexpdf && POPD || GOTO :error

	REM Copy the documentation.
	FOR /R "Source\Documentation" %%F IN (*.pdf *.txt) DO CALL :copy "%%~F" "Program\Documentation\%%~nF.pdf" || GOTO :error
	ROBOCOPY /MIR /NJH /NJS "Source\Documentation\SampleFiles" "Program\Documentation\SampleFiles"
	IF %ERRORLEVEL% GEQ 8 GOTO :error

	REM Copy the documentation separately.
	FOR /R "Program\Documentation" %%F IN (*.pdf) DO CALL :copy "%%~F" "OpenRails-%Mode%-%%~nxF" || GOTO :error
)

IF "%Mode%" == "Stable" (
	ROBOCOPY /MIR /NJH /NJS "Program" "Open Rails\Program" /XD Documentation
	IF %ERRORLEVEL% GEQ 8 GOTO :error
	ROBOCOPY /MIR /NJH /NJS "Program\Documentation" "Open Rails\Documentation"
	IF %ERRORLEVEL% GEQ 8 GOTO :error
	>"Source\Installer\OpenRails shared\Version.iss" ECHO #define MyAppVersion "%Version%.%Revision%" || GOTO :error
	iscc "Source\Installer\OpenRails from download\OpenRails from download.iss" || GOTO :error
	iscc "Source\Installer\OpenRails from DVD\OpenRails from DVD.iss" || GOTO :error
	CALL :move "Source\Installer\OpenRails from download\Output\OpenRailsTestingSetup.exe" "OpenRails-%Mode%-Setup.exe" || GOTO :error
	CALL :move "Source\Installer\OpenRails from DVD\Output\OpenRailsTestingDVDSetup.exe" "OpenRails-%Mode%-DVDSetup.exe" || GOTO :error
	REM *** Special build step: signs binaries ***
	IF NOT "%JENKINS_TOOLS%" == "" CALL "%JENKINS_TOOLS%\sign.cmd" "OpenRails-%Mode%-Setup.exe" || GOTO :error
	IF NOT "%JENKINS_TOOLS%" == "" CALL "%JENKINS_TOOLS%\sign.cmd" "OpenRails-%Mode%-DVDSetup.exe" || GOTO :error
)

REM Create binary and source zips.
CALL :delete "OpenRails-%Mode%*.zip" || GOTO :error
PUSHD "Program" && 7za.exe a -r -tzip -x^^!*.xml "..\OpenRails-%Mode%.zip" . && POPD || GOTO :error
7za.exe a -r -tzip -x^^!.* -x^^!obj -x^^!lib -x^^!_build -x^^!*.bak -x^^!Website "OpenRails-%Mode%-Source.zip" "Source" || GOTO :error

ENDLOCAL
GOTO :EOF

REM Lists or checks for a single tool
:list-or-check-tool
IF "%CheckToolInPath.Check%" == "0" GOTO :list-tool
IF "%CheckToolInPath.Check%" == "1" GOTO :check-tool
GOTO :EOF

REM Lists a tool using the same arguments as :check-tool
:list-tool
SETLOCAL
SET Tool.File=%~1                      .
SET Tool.Name=%~2                                                  .
ECHO   - %Tool.File:~0,22% %Tool.Name:~0,52%
ENDLOCAL
GOTO :EOF

REM Checks for a tool (%1) exists in %PATH% and reports a warning otherwise (%2 is descriptive name for tool).
:check-tool
IF "%~$PATH:1" == "" (
	>&2 ECHO WARNING: %~1 ^(%~2^) is not found in %%PATH%% - the build may fail.
	SET /A CheckToolInPath.Missing=CheckToolInPath.Missing+1
)
GOTO :EOF

REM Utility for creating a directories with logging.
:create
ECHO Create "%~1"
IF NOT EXIST "%~1" MKDIR "%~1"
GOTO :EOF

REM Utility for recreating a directories with logging.
:recreate
ECHO Recreate "%~1"
(IF EXIST "%~1" RMDIR "%~1" /S /Q) && MKDIR "%~1"
GOTO :EOF

REM Utility for moving files with logging.
:move
ECHO Move "%~1" "%~2"
1>nul MOVE /Y "%~1" "%~2"
GOTO :EOF

REM Utility for copying files with logging.
:copy
ECHO Copy "%~1" "%~2"
1>nul COPY /Y "%~1" "%~2"
GOTO :EOF

:delete
ECHO Delete "%~1"
IF EXIST "%~1" DEL /F /Q "%~1"
GOTO :EOF

REM Reports that an error occurred.
:error
>&2 ECHO ERROR: Failure during build ^(check the output above^). Error %ERRORLEVEL%.
EXIT /B 1

#!/bin/bash

# Bash immediate exit and verbosity
set -ev

# from smlib travis tests
SMPATTERN="http:.*sourcemod-.*-linux\..*"
SMURL="http://www.sourcemod.net/smdrop/$SMVERSION/"
SMPACKAGE=`lynx -dump "$SMURL" | egrep -o "$SMPATTERN" | tail -1`

# get sourcemod package and copy plugin code into scripting folder
if [ ! -d "build" ]; then
	mkdir build
	cd build
	wget $SMPACKAGE
	tar -xzf $(basename "$SMPACKAGE")
	rm addons/sourcemod/scripting/*.sp
	cp -R ../scripting/ addons/sourcemod/

	# get dependency libraries.
	git clone https://github.com/bcserv/smlib.git
	cp -R smlib/scripting/include/ addons/sourcemod/scripting/

	git clone https://github.com/Impact123/AutoExecConfig.git
	cp AutoExecConfig/autoexecconfig.inc addons/sourcemod/scripting/include/

	hg --config hostsecurity.disabletls10warning=true clone https://bitbucket.org/Drifter321/dhooks2
	cp dhooks2/sourcemod/scripting/include/dhooks.inc addons/sourcemod/scripting/include/

	git clone https://github.com/Drixevel/Chat-Processor.git
	cp Chat-Processor/scripting/include/chat-processor.inc addons/sourcemod/scripting/include/
	
	git clone https://bitbucket.org/minimoney1/simple-chat-processor.git
	cp simple-chat-processor/scripting/include/scp.inc addons/sourcemod/scripting/include/
	
	git clone https://github.com/KissLick/ColorVariables.git
	cp ColorVariables/addons/sourcemod/scripting/includes/colorvariables.inc addons/sourcemod/scripting/include/
	
	cd ..
fi

# setup the auto version file to have the git revision in the version convar.
# get the correct revision count
# https://github.com/travis-ci/travis-ci/issues/3412
git fetch --unshallow
GITREVCOUNT=$(git rev-list --count HEAD)

echo -e "#if defined _smrpg_version_included\n#endinput\n#endif\n#define _smrpg_version_included\n\n" > build/addons/sourcemod/scripting/include/smrpg/smrpg_autoversion.inc
echo -e "#define SMRPG_VERSION \"1.0-$GITREVCOUNT\"\n" >> build/addons/sourcemod/scripting/include/smrpg/smrpg_autoversion.inc
	
# setup package folders
PACKAGEDIR=$(pwd)/package
if [ ! -d "package" ]; then
	mkdir package
	mkdir package/plugins
	mkdir package/plugins/upgrades
fi

cp -R configs/ package/
cp -R gamedata/ package/
cp -R scripting/ package/
cp -R translations/ package/

# compile the plugins
cd build/addons/sourcemod/scripting/
chmod +x spcomp

# compile base plugins
for f in *.sp
do
	if [ "$f" != "smrpg_chattags.sp" ]; then
		echo -e "\nCompiling $f..."
		smxfile="`echo $f | sed -e 's/\.sp$/\.smx/'`"
		./spcomp $f -o$PACKAGEDIR/plugins/$smxfile -E
	fi
done

# compile both versions of chattags for both chat processors..
echo -e "\nCompiling smrpg_chattags.sp for Chat Processor..."
./spcomp smrpg_chattags.sp -o$PACKAGEDIR/plugins/smrpg_chattags_cp.smx -E

echo -e "\nCompiling smrpg_chattags.sp for Simple Chat Processor..."
./spcomp smrpg_chattags.sp -o$PACKAGEDIR/plugins/smrpg_chattags_scp.smx -E USE_SIMPLE_PROCESSOR=

# compile all upgrades
for f in upgrades/*.sp
do
	# skip the skeleton
	if [ "$f" != "upgrades/smrpg_upgrade_example.sp" ]; then
		echo -e "\nCompiling upgrade $f..."
		smxfile="`echo $f | sed -e 's/\.sp$/\.smx/'`"
		./spcomp $f -o$PACKAGEDIR/plugins/$smxfile -E
	fi
done

# put the files into a nice archive
cd $PACKAGEDIR
ARCHIVE=smrpg-rev$GITREVCOUNT.tar.gz
tar -zcvf ../$ARCHIVE *
cd ..

# upload package
# TODO: put into seperate deploy script
if [ ! -z "$DROPURL" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ] && [ "$TRAVIS_BRANCH" == "master" ]; then
	curl -F "sm=$SMVERSION" -F "key=$UPLOADKEY" -F "drop=@$ARCHIVE" $DROPURL
fi

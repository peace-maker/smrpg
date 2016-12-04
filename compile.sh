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

	hg clone https://bitbucket.org/Drifter321/dhooks2
	cp dhooks2/sourcemod/scripting/include/dhooks.inc addons/sourcemod/scripting/include/

	cd ..
fi
	
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
	echo -e "\nCompiling $f..."
	smxfile="`echo $f | sed -e 's/\.sp$/\.smx/'`"
	./spcomp $f -o$PACKAGEDIR/plugins/$smxfile -E
done

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
GITREVCOUNT=$(git rev-list --count HEAD)
ARCHIVE=smrpg-rev$GITREVCOUNT.tar.gz
cd $PACKAGEDIR
tar -zcvf ../$ARCHIVE *
cd ..

# upload package
if [ ! -z "$DROPURL" ]; then
	curl -F "sm=$SMVERSION" -F "key=$UPLOADKEY" -F "drop=@$ARCHIVE" $DROPURL
fi

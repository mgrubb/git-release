#!/bin/sh

### Author: Michael Grubb <mtg@dailyvoid.com>
### File:   /Users/mgrubb/tmp/release/release.sh
### Description: release.sh -- <+ SHORT_DESC +>
### Copyright: (C) 2010-2012, Michael Grubb <mtg@dailyvoid.com>
### Modeline: vim:tw=79:sw=4:ts=4:ai:
### License: BSD (See README)

PROG=$(basename $0)
USAGE="Usage: $PROG operation args
	Where operation is:
		major -- Create a new release and bump the
			 major version number (only on master)

		minor -- Create a new release and bump the
			 minor version number (only on master)

		patch -- Create a new release and bump the
			 patch version number (on master or release)

		bump -- Same as '$PROG make patch'
		commit -- Finalizes the release branch and merges to master
		rollback -- Discard the release branch, must be on the release branch.
			-force -- Force rollback on an unmerged branch.
		setinfo -- Configures the project for use with $PROG.
		getinfo -- Prints the project configuration values.
		tar -- Generates a self-extracting tar file for the current version.
		version -- Show the current project version.
"

CONFERR="$PROG: Error: Coult not get %s from git config.
              Use '$PROG setinfo' to set project info."

if [ "$#" -lt 1 ]
then
	echo "$USAGE" >&2
	exit 1
fi

if [ ! -d .git/. ]
then
	echo "$PROG: Error: $PROG must be run at the root of a git working directory " >&2
	exit 1
fi

knob="r"

# Grab the configuration from .git/config
alias gitconfig="git config --file .releaserc"
CONFIGED="$(gitconfig --get release.configured)"

if [ -z "$CONFIGED" -a "$1" != "setinfo" ]
then
	echo "$PROG: Error: Project not configured, run $PROG setinfo first." >&2
	exit 1
fi

VERSIONFILE=$(gitconfig --get project.versionfile)
VERSIONLANG=$(gitconfig --get project.versionlang)
VERSIONLANG=${VERSIONLANG:+"-l $VERSIONLANG"}
lname="$(gitconfig --get project.name)"
sname="$(gitconfig --get project.archname)"
ename="$(gitconfig --get project.sescript)"
delrelb="$(gitconfig --get release.delrelbranches)"
bprefix="$(gitconfig --get release.branchprefix)"

# Are we already on a release branch?
grep -q $bprefix .git/HEAD 2>/dev/null && \
	onrelease=$(cat .git/HEAD | cut -f3- -d/)

case "$1" in
	major|minor)
		if [ -n "$onrelease" ]
		then
			echo "$PROG: Error: cannot change major or minor \
version numbers on a release 
            branch, commit or rollback first." >&2
			exit 1
		else
			mode="make"
			case "$1" in
				major) knob="v" ;;
				minor) knob="r" ;;
			esac
		fi ;;
	patch)	mode="make" ; knob="l" ;;

	tar) mode="tar" ;;
	bump) mode="make" ; knob="l" ;;
	commit) mode="commit" ;;
	rollback) mode="rollback"
			  [ "$2" = "-force" ] && force=y ;;
	setinfo) mode="setinfo" ;;
	getinfo) mode="getinfo" ;;
	version) mode="version" ;;
	*) echo "$USAGE" >&2 ; exit 1;;
esac

trap 'rm -Rf $infofile $VERSIONFILE.tmp ${sname}$$ >/dev/null 2>&1;' \
	EXIT TERM KILL INT 

cver=$(tools/shtool version $VERSIONLANG -d short "$VERSIONFILE")
aver=$cver

if [ "$mode" = "version" ]
then
	echo "$cver"
	exit 0
fi

if [ "$mode" = "make" ]
then

	# we calculate the new version here so that we know what the name of the
	# branch is going to be and so that we aren't making changes before the
	# branch is created.
	cp "$VERSIONFILE" "$VERSIONFILE.tmp"
	nver=$(tools/shtool version $VERSIONLANG -i $knob "$VERSIONFILE.tmp" | \
			sed -e 's/^new version: \([^ 	]*\) .*$/\1/')
	rm $VERSIONFILE.tmp >/dev/null 2>&1

	# make branch if we aren't already on a release branch
	# else rename the branch to the new version number
	if [ -z "$onrelease" ]
	then
		git checkout -b $bprefix$nver master
	else
		git branch -m $bprefix$nver
	fi

	# bump version
	tools/shtool version $VERSIONLANG -n "$lname" \
		-s $nver "$VERSIONFILE" >/dev/null 2>&1

	# commit version change
	if [ -n "$onrelease" ]
	then
		git commit -a -m "Updating patch level to $nver"
	else
		git commit -a -m "Created release branch for $nver"
	fi

	onrelease=$bprefix$nver
	aver=$nver
	mode="tar"
fi

if [ "$mode" = "commit" ]
then
	if [ -z "$onrelease" ]
	then
		echo "$PROG: Error: Not on a release branch." >&2
		exit 1
	fi

	# check for uncommited changes
	if [ -n "$(git status -s)" ]
	then
		echo "$PROG: Error: Uncommited changes on the release branch. Run 'git commit -a' first." >&2
		exit 1
	fi

	# switch back to the master branch, merge the banch
	# if the release.delrelbranches is set then delete the release branches.
	git checkout master
	git merge $onrelease
	if [ "$delrelb" = "true" ]
	then
		git branch -d $onrelease
	fi
	git tag $onrelease

	onrelease=""
	mode="tar"
fi


if [ "$mode" = "tar" ]
then
	if [ -n "$onrelease" ]
	then
		aver=$(echo $aver | tr p b)
	fi 
	# cut a tarball
	msargs="--nox11"
	if [ -z "$ename" ]
	then
		msargs="$msargs --notemp"
	fi

	git archive --format=tar --prefix=${sname}$$/$sname-$aver/ HEAD | \
	tar xf - && \
	tools/makeself.sh \
		$msargs \
		${sname}$$/$sname-$aver \
		${sname}-$aver.run \
		"$lname" ${ename:+"./$ename"} && rm -Rf ${sname}$$
fi

if [ "$mode" = "setinfo" -o "$mode" = "getinfo" ]
then

	if [ -n "$CONFIGED" ]
	then
		_versionfile="$(gitconfig --get project.versionfile)"
		_versionlang="$(gitconfig --get project.versionlang)"
		_projectname="$(gitconfig --get project.name)"
		_archivename="$(gitconfig --get project.archname)"
		_scriptname="$(gitconfig --get project.sescript)"
		_delrelbranches="$(gitconfig --get release.delrelbranches)"
		_branchprefix="$(gitconfig --get release.branchprefix)"
	fi

	: ${_versionfile:="VERSION"}
	: ${_versionlang:="txt"}
	: ${_projectname:="Untitled Project"}
	: ${_archivename:="archive"}
	: ${_delrelbranches:="yes"}
	: ${_branchprefix:="release-"}

		infofile="/tmp/release-info-$$.txt"
		cat << EOF > $infofile
Project Settings:
Version file name (relative to root of project): ${_versionfile}
Version file language (valid values: c, m4, perl, python, txt): ${_versionlang}
Project Name: ${_projectname}
Archive Base Name: ${_archivename}
Script to run after self-extraction (relative to root of project): ${_scriptname}

Release Options:
Release Branch Prefix: ${_branchprefix}
Delete release branches after merge (yes/no)?: ${_delrelbranches}
EOF

	if [ "$mode" = "getinfo" ]
	then
		cat $infofile
		exit 0
	fi

	{ [ -e "$VISUAL" ] && INFOED="$VISUAL" ;} || \
	{ [ -e "$EDITOR" ] && INFOED="$EDITOR" ;} || \
	{ [ -e /usr/bin/vi ] && INFOED=/usr/bin/vi ;} || \
	{ [ -e /bin/vi ] && INFOED=/usr/bin/vi ;} || \
	{ [ -n "$(which vi)" ] && INFOED=vi ;} || \
	{ echo "$PROG: Error: Could not find and editor." ;  exit 1 ;}

	$INFOED $infofile

	if [ "$?" != "0" ]
	then
		echo "$PROG: Error: Editor returned non-zero, exiting"
		exit 1
	fi
	_versionfile="$(sed -n -e 's/^Version file name.*: \(.*\)$/\1/p' $infofile)"
	_versionlang="$(sed -n -e 's/^Version file language.*: \(.*\)$/\1/p' $infofile)"
	_projectname="$(sed -n -e 's/^Project Name: \(.*\)$/\1/p' $infofile)"
	_archivename="$(sed -n -e 's/^Archive Base Name: \(.*\)$/\1/p' $infofile)"
	_scriptname="$(sed -n -e 's/^Script.*: \(.*\)$/\1/p' $infofile)"
	_delrelbranches="$(sed -n -e 's/^Delete.*: \(.*\)$/\1/p' $infofile)"
	_branchprefix="$(sed -n -e 's/^Release Branch Prefix: \(.*\)$/\1/p' $infofile)"
	rm $infofile >/dev/null 2>&1

	gitconfig project.versionfile "$_versionfile"
	gitconfig project.versionlang "$_versionlang"
	gitconfig project.name "$_projectname"
	gitconfig project.archname "$_archivename"
	gitconfig project.sescript "$_scriptname"
	gitconfig --bool release.delrelbranches "$_delrelbranches"
	gitconfig release.branchprefix "$_branchprefix"
	gitconfig --bool release.configured true

fi

if [ "$mode" = "rollback" ]
then
	if [ -z "$onrelease" ]
	then
		echo "$PROG: Error: Must be on the release branch before rolling it back." >&2
		exit 1
	fi

	master=$(git rev-parse master)
	parent=$(git rev-parse ${onrelease}^1)
	if [ "$master" != "$parent" -a -z "$force" ]
	then
		echo "$PROG: Error: There is more than one commit on this branch, by rolling back you may loose work, to continue re-run the command with the -force option." >&2
		exit 1
	else
		git checkout master
		git branch -D $onrelease
	fi
fi

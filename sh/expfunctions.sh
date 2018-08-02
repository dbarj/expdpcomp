#!/bin/ksh
# ----------------------------------------------------------------------------
#
# expdpcomp - expdp with gzip compression
# Copyright 2012  Rodrigo Jorge <http://www.dbarj.com.br/>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ----------------------------------------------------------------------------

###############################################
###############################################
#########                             #########
#########           WARNING           #########
#########   DO NOT TOUCH THIS FILE    #########
#########                             #########
###############################################
###############################################

###############################################
###############################################
####                                      #####
####     ANY MODIFICATION MUST BE DONE    #####
####     INSIDE "oracle_sid.cfg" FILE     #####
####                                      #####
###############################################
###############################################

# Function to print in log file.
imprime ()
{
	echo "$(date "+%F %T") - $1"
}

# Function to exit this script.
exitscript ()
{
	if [ "$PWDFILE" != "" -a "$EXPDEBUG" != "1" ]
	then
		test -f $PWDFILE && (imprime "Removing password file..."; rm -f $PWDFILE)
	fi
	if [ "$EXPPIPE" != "" ]
	then
		test -p $EXPPIPE && (imprime "Removing pipe..."; rm -f $EXPPIPE)
	fi
	exit $1
}

# Function to verify if bin exists.
bincheck ()
{
	run=$(which $1)
	ret=$?

	if [ $ret -ne 0 -o "$(echo $run | $HEADCMD 1)" != "/" ]
	then
		imprime "The \"$1\" command could not be found. Please add to PATH..."
		exitscript 1
	fi
}

# Function to verify if variable is declared.
varcheck ()
{
	run=$(eval "echo \"\$$1\"")
	if [ "$run" = "" ]
	then
		imprime "Variable \"$1\" not defined in parameter file..."
		exitscript 1
	fi
}

# Function to return if file is being used.
fileusedchk ()
{
	# 1 - Being used
	# 0 - Unused
	
	if [ "$SOTYPE" = "HP-UX" ]
	then
		run=$(fuser $1 2>&- | wc -l)
	elif [ "$SOTYPE" = "Linux" ]
	then
		run=$(ls -la /proc/*/fd/* 2>&- | grep $1 | wc -l)
	elif [ "$SOTYPE" = "SunOS" ]
	then
		run=$(fuser $1 2>&- | wc -w)
	fi

	if [ "$run" = "1" ]
	then
		return 1
	else
		return 0
	fi
}

# Function to run with trap.
abortexp ()
{
	imprime "Aborting execution. Received \"$1\".."
	imprime "Killing child processes.."
	pgrep -P $$ | xargs kill -$1
	exitscript 1
}

SOTYPE=$(uname -s)

if [ "$SOTYPE" = "HP-UX" ]
then
	HEADCMD="head -c -n"
	ORATAB_FILE=/etc/oratab
	IDCMD=id
	AWKCMD=awk
elif [ "$SOTYPE" = "SunOS" ]
then
	HEADCMD="cut -c"
	ORATAB_FILE=/var/opt/oracle/oratab
	IDCMD=/usr/xpg4/bin/id
	AWKCMD=/usr/xpg4/bin/awk
elif [ "$SOTYPE" = "Linux" ]
then
	HEADCMD="head -c"
	ORATAB_FILE=/etc/oratab
	IDCMD=id
	AWKCMD=awk
else # ???
	imprime "S.O. \"$SOTYPE\" not yet supported.."
	exitscript 1
fi

trap "abortexp TERM" TERM

test "$EXPDEBUG" = "1" && set -x

true # This line must be the last and must stay here
####
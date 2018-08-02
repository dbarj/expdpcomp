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

WORKDIR=$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P) # Folder of this script

. $WORKDIR/expfunctions.sh
ret=$?

if [ $ret -ne 0 ]
then
	echo "Could not load shell function file \"$WORKDIR/expfunctions.sh\"."
	exit 1
fi

imprime "Beginning of the export process..."

if [ $# -ne 1 ]
then
	imprime "One argument is needed..."
	exitscript 1
fi

export ORACLE_SID=$1

imprime "Checking O.S..."
run=$(uname -s)
imprime "O.S: $run"

bincheck $IDCMD
bincheck $AWKCMD

if [ "$($IDCMD -u)" = "0" ]; then
	imprime "Should not be executed as root..."
	exitscript 1
fi

if [ ! -f $WORKDIR/../cfg/${ORACLE_SID}.cfg ]
then
	imprime "The parameter file \"${ORACLE_SID}.cfg\" does not exist on folder $(cd -P -- "$WORKDIR/../cfg" && pwd -P)"
	if [ ! -f $WORKDIR/../cfg/default.cfg ]
	then
		imprime "The parameter file \"default.cfg\" does not exist on folder $(cd -P -- "$WORKDIR/../cfg" && pwd -P)"
		exitscript 1
	fi
	PARFILE=default.cfg
else
	PARFILE=${ORACLE_SID}.cfg
fi

imprime "Loading parameters \"$PARFILE\""
. $WORKDIR/../cfg/$PARFILE # Load parameter file.

varcheck "EXPRETENTION"
varcheck "EXPUSER"
varcheck "EXPDEST"
varcheck "COMPALG"
test "$EXPTYPE" = "" && EXPTYPE="EXP"

if [ ! -d $EXPDEST ]
then
	imprime "Destination folder \"$EXPDEST\" is inaccessible..."
	exitscript 1
fi

if [ "$RESOLVTNS" = "" ]
then
	run=$(grep $ORACLE_SID $ORATAB_FILE)
	ret=$?

	if [ $ret -ne 0 ]
	then
		imprime "Oracle SID \"$ORACLE_SID\" is not registered in $ORATAB_FILE"
		exitscript 1
	fi

	# Oracle Settings
	imprime "Calling ORAENV..."
	export ORAENV_ASK=NO
	bincheck "oraenv"
	. oraenv $ORACLE_SID
else
	bincheck "tnsping"
	run=$(tnsping $RESOLVTNS)
	ret=$?
	
	if [ $ret -ne 0 ]
	then
		imprime "Oracle Database \"$RESOLVTNS\" is not registered in tnsnames.ora"
		exitscript 1
	fi
	
	#if [ "$EXPTYPE" = "EXPDP" ]
	#then
	#	imprime "Only local database is allowed in EXPDP mode. Please comment \"\$RESOLVTNS\""
	#	exitscript 1
	#fi
	
	EXPUSER="$EXPUSER"@$RESOLVTNS
	
fi

DATAHOJE=`date +%Y%m%d_%H%M%S`
EXPFILE=${EXPTYPE}_${ORACLE_SID}_FULL_${DATAHOJE}  # DUMP file prefix. NEVER USE DOTS HERE. Would bug split scripts.
EXPPIPE=$EXPDEST/$EXPFILE.pipe

bincheck "mktemp"
PWDFILE=$(mktemp) # File that stores the password
echo "userid=$EXPUSER">$PWDFILE

imprime "Checking file extension..."
run=$(echo $COMPALG | $AWKCMD 'BEGIN { FS = "/" } ; { print $NF }' | $AWKCMD 'BEGIN { FS = " " } ; { print $1 }')

if [ "$run" = "gzip" ] #Gzip
then
	imprime "Extension: gzip..."
	EXPEXT="gz"
elif [ "$run" = "bzip2" ] #Bzip2
then
	imprime "Extension: bzip2..."
	EXPEXT="bz2"
else #Unkown
	imprime "Extension: UNKOWN..."
	imprime "Only gzip or bzip2 may be used..."
	exitscript 1
fi

bincheck $(echo $COMPALG | $AWKCMD 'BEGIN { FS = " " } ; { print $1 }')

if [ "$EXPTYPE" = "EXP" ]
then
	bincheck "mknod"
	bincheck "exp"
	imprime "Calling piped script of compression..."
	mknod $EXPPIPE p
	EXPDUMP=$EXPDEST/${EXPFILE}.dmp.${EXPEXT}
	$COMPALG  < $EXPPIPE > $EXPDUMP &
	COMPID=$!
	imprime "Starting EXP of instance ${ORACLE_SID}..."
	if [ "$EXPPARAM" = "" ]
	then
		EXPPARAM="full=y consistent=y compress=n statistics=none direct=y buffer=9999999"
		imprime "Loading default exp parameters: \"$EXPPARAM\""
	else
		imprime "Loading custom exp parameters: \"$EXPPARAM\""
	fi
	if [ "$EXPSKIPTABLE" != "" ]
	then
		imprime "Skipping tables: \"$EXPSKIPTABLE\""
		### Find tables inside Oracle
		bincheck "sqlplus"
		ARQSQL="$(mktemp).sql"
		run="sqlplus -l -s $EXPUSER @$ARQSQL"
		echo "set echo off heading off feed off verify off pages 0 " >> $ARQSQL
		echo "select trim(table_name) || decode(                   " >> $ARQSQL
		echo "       row_number () over (order by table_name),     " >> $ARQSQL
		echo "       count (*) over (),'',',')                     " >> $ARQSQL
		echo "from   user_tables                                   " >> $ARQSQL
		echo "where  table_name not in ($EXPSKIPTABLE);            " >> $ARQSQL
		echo "exit                                                 " >> $ARQSQL
		EXPTB=$($run)
		ret=$?
		test "$EXPDEBUG" != "1" && rm -f $ARQSQL
		if [ $ret -ne 0 ]
		then
			imprime "Could not skip table \"${EXPSKIPTABLE}\"."
			imprime "sqlplus returned ${ret}: $EXPTB"
			exitscript 1
		fi
		if [ "$EXPTB" = "" ]
		then
			imprime "Could not skip table \"${EXPSKIPTABLE}\"."
			imprime "Zero lines returned."
			exitscript 1
		fi
		imprime "Restricting export to tables: \"${EXPTB}\"."
		echo "tables=$(echo $EXPTB | tr -d '\040\011\012\015')" >> $PWDFILE
	fi
	if [ "$EXPDEBUG" != "1" ]
	then
		exp file=$EXPPIPE log=$EXPDEST/${EXPFILE}.log parfile=$PWDFILE $EXPPARAM 2>&- &
	else
		exp file=$EXPPIPE log=$EXPDEST/${EXPFILE}.log parfile=$PWDFILE $EXPPARAM 2>&1 1>$EXPDEST/${EXPFILE}.exp.log &
	fi
	EXPPID=$!
	
	wait $EXPPID
	expret=$?
	if [ $expret -ne 0 -a ! -f $EXPDUMP ]
	then
		kill -9 $COMPID 2>&-
	fi
elif [ "$EXPTYPE" = "EXPDP" ]
then
	bincheck "expdp"
	varcheck "EXPPARALLEL"
	varcheck "EXPFILESIZE"
	varcheck "TARCOMPACT"
	bincheck "$WORKDIR/expdpcompress.sh"

	### Find folder name inside Oracle
	bincheck "sqlplus"
	ARQSQL="$(mktemp).sql"
	run="sqlplus -l -s $EXPUSER @$ARQSQL"
	echo "set echo off heading off feed off verify off " >> $ARQSQL
	echo "select min(directory_name)                   " >> $ARQSQL
	echo "from   dba_directories                       " >> $ARQSQL
	echo "where  directory_path = '${EXPDEST}' or      " >> $ARQSQL
	echo "       directory_path = '${EXPDEST}/';       " >> $ARQSQL
	echo "exit                                         " >> $ARQSQL
	DPDIR=$($run)
	ret=$?
	test "$EXPDEBUG" != "1" && rm -f $ARQSQL
	
	if [ $ret -ne 0 ]
	then
		imprime "Could not find Oracle Directory for \"${EXPDEST}\"."
		imprime "sqlplus returned ${ret}: $DPDIR"
		exitscript 1
	fi
	if [ "$DPDIR" = "" ]
	then
		imprime "Could not find Oracle Directory for \"${EXPDEST}\"."
		imprime "Run: --create directory EXPDP1 as '${EXPDEST}';"
		exitscript 1
	fi
	
	imprime "Starting EXPDP of instance ${ORACLE_SID}..."	
	if [ "$EXPPARAM" = "" ]
	then
		EXPPARAM="full=Y flashback_time=systimestamp"
		imprime "Loading default expdp parameters: \"$EXPPARAM\""
	else
		imprime "Loading custom expdp parameters: \"$EXPPARAM\""
	fi
	if [ "$EXPDEBUG" != "1" ]
	then
		expdp parfile=${PWDFILE} directory=${DPDIR} dumpfile=${EXPFILE}.%u.dmp logfile=${EXPFILE}.log filesize=${EXPFILESIZE} parallel=${EXPPARALLEL} $EXPPARAM 2>&- &
	else
		expdp parfile=${PWDFILE} directory=${DPDIR} dumpfile=${EXPFILE}.%u.dmp logfile=${EXPFILE}.log filesize=${EXPFILESIZE} parallel=${EXPPARALLEL} $EXPPARAM 2>&1 1>$EXPDEST/${EXPFILE}.exp.log &
	fi
	EXPPID=$!
	
	imprime "Calling parallel script of compression..."
	$WORKDIR/expdpcompress.sh $EXPFILE $EXPPID $PARFILE &
	COMPID=$!
	
	wait $EXPPID
	expret=$?
else
	imprime "EXPTYPE parameter must be either EXP or EXPDP. Found: $EXPTYPE"
	exitscript 1
fi

imprime "Export command returned: $expret"

############ Remove old Dumps

imprime "Cleaning files older than $EXPRETENTION days..."

for line in `ls -1td $EXPDEST/*${ORACLE_SID}*.dmp* 2>&- | grep -v ${EXPFILE} | sed -e "1d"` # For each dump file, except current and last.
do
	if test -f $line && test `find $line -type f -mtime +${EXPRETENTION} 2>&-` # Remove dump file if older than retention variable.
	then
		imprime "Deleting old file: $line"
		rm -f $line # Remove file
		lineprefix=$(echo $line | $AWKCMD 'BEGIN{FS=OFS="/"}{$NF=""; NF--; print}')/$(echo $line | $AWKCMD 'BEGIN { FS = "/" } ; { print $NF }' | $AWKCMD 'BEGIN { FS = "." } ; { print $1 }') # Full file path until first dot in filename
		test -f ${lineprefix}.log && (imprime "Deleting old log:  ${lineprefix}.log"; rm -f ${lineprefix}.log) # Remove log from file above
	fi
	if test -d $line && test `find $line -type d -mtime +${EXPRETENTION} 2>&-` # Remove dump folder if older than retention variable.
	then
		imprime "Deleting old folder: $line"
		rm -rf $line # Remove folder
	fi
done

############ Remove orphan Logs

for line in `ls -1td $EXPDEST/*${ORACLE_SID}*.log 2>&- | grep -v ${EXPFILE}` # For each log file, except current.
do
	if test -f $line && test `find $line -type f -mtime +30` # If older than 30 days.
	then
		lineprefix=$(echo $line | $AWKCMD 'BEGIN{FS=OFS="/"}{$NF=""; NF--; print}')/$(echo $line | $AWKCMD 'BEGIN { FS = "/" } ; { print $NF }' | $AWKCMD 'BEGIN { FS = "." } ; { print $1 }') # Full file path until first dot in filename
		test `find ${lineprefix}*.dmp* -type f 2>&-` || (imprime "Deleting orphan log file: $line"; rm -f $line) # Only delete if there is no dump associated
	fi
done

imprime "Waiting the end of compress script..."
wait $COMPID # Wait the end of compression

imprime "End of the export process..."

exitscript $expret
####
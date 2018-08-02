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

imprime "Beginning of the process to compact EXPDP..."

if [ $# -ne 3 ]
then
	imprime "Three arguments are needed..."
	exit 1
fi

EXPFILE=$1      # Do not touch. File prefix name.
EXPPID=$2       # Do not touch. PID of father process.
PARFILE=$3      # Do not touch. Parameter file name.

. $WORKDIR/../cfg/$PARFILE # Load parameter file.

MAXPARALLEL=10                 # Max concurrent compressions.
SLEEPWAIT=30                   # Sleep wait time.
EXPDIRNAME=${EXPFILE}.dmp.DIR  # Folder name for DUMP files.

EXPFILESIZE=`echo "$(echo $EXPFILESIZE | sed 's/.$//') * 1024 * 1024 * 1024" | bc` # expr command fail on HP-UX

cd $EXPDEST
sleep $SLEEPWAIT

retProc=0
ultvez=0 # Flag, receive 1 one the very last loop, when father PID is dead.

while [ $retProc -eq 0 -o $ultvez -eq 1 ] # While father PID exists.
do
	for line in `ls -1 ${EXPFILE}*.dmp 2>&-` # For each DUMP file.
	do
		run=`ls $line.* 2>&-` # Verify if it is already being zipped.
		retThis=$?
		
		if [ $retThis -ne 0 ]
		then
			run=`ls ${EXPFILE}.$(printf "%02d" "$(expr $(echo $line | $AWKCMD 'BEGIN { FS = "." } ; { print \$2 }') + 1)").dmp* 2>&-` # Verify if next file exists.
			retNext=$?
			
			run=`fileusedchk $line` # Verify if file is being used.
			retUsed=$?
			
			size=`ls -l $line | $AWKCMD 'BEGIN { FS = " " } ; { print $5 }'` # Verify file size.
			zipcnt=`ps -ef | grep "${COMPALG} ${EXPFILE}" | grep -v grep | wc -l` # Verify how many zips are running at the moment.

			if [ $retNext -eq 0 -a $size -eq ${EXPFILESIZE} -a $zipcnt -le ${MAXPARALLEL} -a $retUsed -eq 0 ]
			then
				imprime "Compacting $line"
				nohup ${COMPALG} $line &
			elif [ $ultvez -eq 1 ] # If this is the last loop.
			then
				imprime "Compacting $line"
				nohup ${COMPALG} $line &
			fi
		fi
	done
	sleep $SLEEPWAIT

	x=`ps -p $EXPPID 2>&-` # Verify if father PID is still there.
	retProc=$?

	if [ $retProc -ne 0 ] # Father PID is dead.
	then
		if [ $ultvez -eq 0 ]
		then
			ultvez=1 # Go into the loop once more.
		else
			ultvez=0 # Already done last loop.
		fi
	fi
done

imprime "Waiting for the end of all compressions..."
zipcnt=1
while [ $zipcnt -ne 0 ] # While there is still any zipping process.
do
	sleep $SLEEPWAIT
	zipcnt=`ps -ef | grep "${COMPALG} ${EXPFILE}" | grep -v grep | wc -l` # How many zipping process.
done

totcnt=`ls -1 ${EXPFILE}*.dmp* 2>&- | wc -l`
if [ $totcnt -ne 0 ]
then
	imprime "Moving files inside DUMP folder..."
	mkdir ${EXPDIRNAME}
	mv ${EXPFILE}.* ${EXPDIRNAME} 2>&-
	if [ $TARCOMPACT -eq 1 ] # If TAR parameter is set.
	then
		mv ${EXPDIRNAME}/${EXPFILE}.log ./ # Put log outside tar file.
		imprime "Creating TAR file..."
		tar -cf ${EXPFILE}.dmp.tar ${EXPDIRNAME}/
		ret=$?
		if [ $ret -eq 0 ] # TAR was successfully created.
		then
			rm -rf ${EXPDIRNAME}/
		fi
	fi
fi

imprime "End of the process to compact EXPDP......"

exit 0
####
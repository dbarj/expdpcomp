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

export PATH=$PATH:/usr/local/bin:/usr/sbin
WORKDIR=$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P) # Folder of this script
logprefix=exp${1}full_$(date +%Y%m%d_%H%M%S)
$WORKDIR/expfull.sh $1 > $WORKDIR/../log/$logprefix.log 2>&1
ret=$?

if [ $ret -ne 0 ]
then
	mv $WORKDIR/../log/$logprefix.log $WORKDIR/../log/${logprefix}_ERROR.log
fi

find $WORKDIR/../log/ -type f -mtime +90 -exec rm -f {} \; # Remove cron logs older than 3 months

exit $ret
####
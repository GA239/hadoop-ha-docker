#!/bin/bash

checkArg () {
  s=0

  if [[ $1 == "-d" ]]; then
    keeprunning=true
    shift 1
    let "s++"
  fi

  if [[ $1 == "-b" ]]; then
    bash=true
    shift 1
    let "s++"
  fi

  shift=$s
}

: ${HADOOP_PREFIX:=/usr/local/hadoop};

$HADOOP_PREFIX/etc/hadoop/hadoop-env.sh

if [ -z $CLUSTER_NAME ]; then
  CLUSTER_NAME="cluster"
  export CLUSTER_NAME
fi

checkArg $@
shift $shift

server="none"
if [[ -z $1 ]]; then
  # start a bash
  bash=true
else
  server=$1
  shift 1
fi

if [ -z $NNODE1_IP ] || [ -z $NNODE2_IP ]  || [ -z $ZK_IPS ] || [ -z $JN_IPS ]; then
  echo NNODE1_IP, NNODE2_IP, JN_IPS and ZK_IPS needs to be set as environment addresses to be able to run.
  exit;
fi


JNODES=$(echo $JN_IPS | tr "," ";")

sed "s/CLUSTER_NAME/$CLUSTER_NAME/" /usr/local/hadoop/etc/hadoop/hdfs-site.xml.template \
| sed "s/NNODE1_IP/$NNODE1_IP/" \
| sed "s/NNODE2_IP/$NNODE2_IP/" \
| sed "s/ZKNODES/$ZK_IPS/" \
| sed "s/JNODES/$JNODES/" \
> /usr/local/hadoop/etc/hadoop/hdfs-site.xml

 mkdir -p /mnt/hadoop/dfs/name && mkdir -p /mnt/hadoop/dfs/data && mkdir -p /mnt/hadoop/journal/data

sed "s/CLUSTER_NAME/$CLUSTER_NAME/" /usr/local/hadoop/etc/hadoop/core-site.xml.template > /usr/local/hadoop/etc/hadoop/core-site.xml

echo SERVER=$server CLUSTER_NAME=$CLUSTER_NAME NNODE1_IP=$NNODE1_IP NNODE2_IP=$NNODE2_IP JNODES=$JNODES ZK_IPS=$ZK_IPS

if [[ $server = "format" ]]; then
   $HADOOP_PREFIX/bin/hadoop namenode -format -nonInteractive
   $HADOOP_PREFIX/bin/hdfs zkfc -formatZK -nonInteractive
   exit
fi

if [[ $server = "standby" ]]; then
   # instead of bootstrapStandby command, we just copy over the data from the mounted directory, which comes from nn1 and exit.
   # Be sure to mount the nn1 volume
   cp -r /mnt/shared/nn1/dfs/name/* /mnt/hadoop/dfs/name/
   exit
fi

if [[ $server != "none" ]]; then
  echo $HADOOP_PREFIX/sbin/hadoop-daemon.sh start $server $@

  $HADOOP_PREFIX/sbin/hadoop-daemon.sh start $server $@
  if [[ $server = "namenode" ]]; then
    $HADOOP_PREFIX/sbin/hadoop-daemon.sh start zkfc
  fi
fi

# press CTRL-C to exit the container
trap 'exit' INT

# Auto exit when the needed processes are not running
if [[ $keeprunning = true ]]; then
  while true; do
    # Only auto close when the daemon is not running. Else it could be a controlled stop
    if [[ -z $(pgrep -f hadoop-daemon.sh) ]]; then
      if [[ $server = "namenode" ]]; then
        if [[ -z $(pgrep -f NameNode) ]]; then echo NameNode not running; $HADOOP_PREFIX/sbin/hadoop-daemon.sh stop zkfc; exit 1; fi
        if [[ -z $(pgrep -f DFSZKFailoverController) ]]; then echo ZKFC not running; $HADOOP_PREFIX/sbin/hadoop-daemon.sh stop namenode; exit 1; fi
      elif [[ $server = "datanode" ]]; then
        if [[ -z $(pgrep -f DataNode) ]]; then echo DataNode not running; exit 1; fi
      elif [[ $server = "journalnode" ]]; then
        if [[ -z $(pgrep -f JournalNode) ]]; then echo JournalNode not running; exit 1; fi
      fi
    else
      echo Hadoop daemon running
    fi
    sleep 3;
  done
fi

if [[ $bash = true ]]; then
  /bin/bash
fi

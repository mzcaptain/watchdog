#!/bin/bash

daemon_switch_ini_file="./switch.ini"
daemon_count_ini_file="./count.ini"
daemon_cmd_ini_file="./cmd.ini"
log_dir="./daemon";

function trim_space()
{
    local string
    local result

    string=$1
    result=`echo $string`
    echo "$result"
}

function read_ini_file()
{
    local key
    local ini_file
    local result

    key=$1
    ini_file=$2
	result=`awk -F '=' '$1~/^'$key' *$/{print $2}' $ini_file`
	result=`echo $result | sed "s/[\"']//g"`
 	echo "$result"
}

function cmd_read_ini_file()
{
    local key
    local ini_file
    local result

    key=$1
    ini_file=$2
	result=`awk -F '=' '$1~/^'$key' *$/{print $2}' $ini_file`
	result=`echo $result | sed "s/[\"']//g"`
 	echo "$result"
}

function write_ini_file()
{
    local key
    local value
    local ini_file
    local result

    key=$1
    value=$2
    ini_file=$3
    result=`sed -i "s/^$key *=.*$/$key = $value/g" $ini_file`
}

function debug_log()
{
   return

    local message
    local time_info

    message=$1
    time_info=`date  +"[%Y-%m-%d %H:%M:%S]"`
    echo "$time_info [DEBUG] $message"
}

function info_log()
{
    local message
    local time_info
    message=$1
    time_info=`date  +"[%Y-%m-%d %H:%M:%S]"`
    echo "$time_info [INFO] $message"
}

function error_log()
{
    local message
    local time_info
    message=$1
    time_info=`date  +"[%Y-%m-%d %H:%M:%S]"`
    echo "$time_info [ERROR] $message"
}

function shutdown_daemon()
{
    local to_kill_daemon
    local cmd
    local proccess_count_cmd
    local proccess_count
    local proccess_kill_cmd

    to_kill_daemon=$1
    cmd=`cmd_read_ini_file "$to_kill_daemon" "$daemon_cmd_ini_file"`
    if [ -z "$cmd" ]; then
        error_log "can not find cmd for $to_kill_daemon"
        return 1
    fi
    proccess_count_cmd="ps xaww | grep -v  'grep' | grep '"$cmd"' |wc -l"
    proccess_count=`eval $proccess_count_cmd`
    if [ "$proccess_count" -eq 0 ]; then
        debug_log "all $to_kill_daemon proccess already gone"
    else
        info_log "killing $to_kill_daemon"
        proccess_kill_cmd="ps -ef | grep -v  'grep' | grep 'php' | grep -v 'php-fpm'  | grep '"$cmd"' | awk '{print \$2}' | xargs kill -1 "
        debug_log "$proccess_kill_cmd"
        eval $proccess_kill_cmd
    fi
    return 0
}

function start_daemon()
{
    local cmd
    local proccess_count_cmd
    local proccess_count
    local proccess_expected_count
    local exec_cmd
    local need_to_open_count
    local daemon_name

    daemon_name=$1

    cmd=`cmd_read_ini_file "$daemon_name" "$daemon_cmd_ini_file"`
    if [ -z "$cmd" ]; then
        error_log "can not find cmd for $daemon_name"
        return 1
    fi
    proccess_count_cmd="ps xaww | grep -v  'grep' | grep '"$cmd"' |wc -l"
    proccess_count=`eval $proccess_count_cmd`

    proccess_expected_count=`read_ini_file "$daemon_name" "$daemon_count_ini_file"`
    if ! (echo $proccess_expected_count | egrep -q '^[0-9]+$'); then
        proccess_expected_count=1
    fi

    if [ "$proccess_count" -lt "$proccess_expected_count" ]; then
        exec_cmd="nohup $cmd > "$log_dir"/"$daemon_name".log 2>&1 &"

        need_to_open_count=`expr $proccess_expected_count - $proccess_count`
        info_log "$daemon_name has $need_to_open_count more proccesses need to start"
        while [ $need_to_open_count -gt 0 ]
        do
            info_log "$exec_cmd"
            eval $exec_cmd
            (( need_to_open_count-- ))
        done
    fi
    return 0
}

while true; do
    while read line
    do
        debug_log "dealing line $line"
        daemon_name=`echo $line | awk -F '=' '{print $1}'`
        daemon_name=`trim_space "$daemon_name"`
        switch=`echo $line | awk -F '=' '{print $2}'`
        switch=`trim_space "$switch"`

        debug_log "daemon name: $daemon_name; switch: $switch"

        if ! (echo $switch | egrep -q '^[0-9]+$'); then
            error_log "wrong switch value"
            continue
        fi

        if [ "$switch" -eq 0 ]; then    #关闭
            debug_log "to shut down: $daemon_name"
            shutdown_daemon "$daemon_name"
            continue
        elif [ "$switch" -eq 1 ]; then  #开启
            debug_log "to start: $daemon_name"
            start_daemon "$daemon_name"
        else                            #重启
            debug_log "to restart: $daemon_name"
            cmd=`cmd_read_ini_file "$daemon_name" "$daemon_cmd_ini_file"`
            if [ -z "$cmd" ]; then
                error_log "can not find cmd for $daemon_name"
                continue
            fi
            proccess_count_cmd="ps xaww | grep -v  'grep' | grep '"$cmd"' |wc -l"
            proccess_count=`eval $proccess_count_cmd`
            if [ "$proccess_count" -eq 0 ]; then
                debug_log "all proccess are already shutted down"
                info_log "start and change $daemon_name switch to 1"
                write_ini_file "$daemon_name" 1 $daemon_switch_ini_file
                start_daemon "$daemon_name"
            else
                info_log "try to shutdown $daemon_name"
                shutdown_daemon "$daemon_name"
                debug_log "waiting proccess to be shutted down"
                continue
            fi
        fi
    done < $daemon_switch_ini_file
    sleep 3
done

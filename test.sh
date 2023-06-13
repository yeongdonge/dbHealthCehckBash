#!/bin/bash
#-------------------------------------------------------------


customer="고객사명"
engineer="엔지니어명"
manager="담당자명"
#read -ep "Enter the DB username : " username
#read -esp "Enter the Password : " password 
echo
#read -ep "Enter the my.cnf path (Absolute Path) : " my_cnf

username=root
password=123
my_cnf=/etc/my.cnf
#-------------------------------------------------------------

# port=$(awk -F '=' '/\[mysqld\]/{flag=1} flag && /^[^#]/ && /port/{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print gensub(/[[:space:]]/, "", "g", $2); flag=0}' ${my_cnf})

#-------------------------------------------------------------
######################### Function Initalize ###################

convert_memory() {
  value=$1
  unit=$2

  case $unit in
    "KB" | "kb")
      converted=$(awk "BEGIN {print $value}")
      echo "Converted Value: $converted KB"
      ;;
    "MB" | "mb")
      converted=$(awk "BEGIN {print $value / 1024 }")
      echo "Converted Value: $converted MB"
      ;;
    "GB" | "gb")
      converted=$(awk "BEGIN {print $value / 1024 / 1024}")
      echo "Converted Value: $converted GB"
      ;;
    *)
      echo "Invalid unit. Supported units: KB, MB, GB"
      ;;
  esac
}

convert_size() {
  local size=$1
  local bias=0

  while [ $size -ge 1024 ]; do
      size=$((size / 1024))
      bias=$((bias + 1))
  done

  case $bias in
    0) unit="Btye";;
    1) unit="KB";;
    2) unit="MB";;
    3) unit="GB";;
    4) unit="TB";;
  esac

  echo "$size$unit"
}


except() {
    echo "   "
    echo "$1"
    echo "Terminated"
    echo "   "
    exit
}

get_cnf_element() {
    element=$(grep "^$1" ${my_cnf} | awk -F "=" '{print $2}' | tr -d ' ')
    echo ${element}
}

get_socket() {
    socket=$(awk -F '=' '/\[mysqld\]/{flag=1} flag && /^[^#]/ && /socket/{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print gensub(/[[:space:]]/, "", "g", $2); flag=0}' ${my_cnf})
    if [ -z "${socket}" ];
    then
        socket=/tmp/mysql.sock
    fi
}


create_extra_cnf() {
echo "
[mysql]
user="${username}"
password="${password}"
socket="${socket}"
" > $1
}


cnf_inavlid_check() {
    if [ ! -f "$1" ];
    then
        except "No such MySQL Configuration file"
    fi
}

basedir_invalid_check() {
    if [ -z "$1" ];
    then
        except "Must include 'basedir' values in ${my_cnf} File."
    fi
}

get_sql_result() {
    client=${basedir}/bin/mysql
    sql_result=$( ${client} --defaults-extra-file=my_ext.cnf -sN -e "$1;" )
    echo ${sql_result}
}

get_os_ver() {
    release_file=$(ls /etc/*release* 2>/dev/null | head -n 1)

    if [[ -f "$release_file" ]]; then
        cat ${release_file}
    fi
}

get_total_mem() {
    mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    echo ${mem_total}
}

get_cpu_model() {
    cpu_model=$(lscpu | grep 'Model name:' | awk -F ':' '{print $2}' | sed -e 's/^[ \t]*//')
    echo ${cpu_model}
}

is_enabled_key_buffer() {
    if [[ $1 -le 0 ]];
    then
        echo '-'
    fi
}

convert_seconds_to_date () {
    days=$(( $1 / ((60 * 60) * 24)))
    hours=$(( $1 / (60 * 60) % 24 )) 

    echo "${days} days ${hours} hours"
}

export_innodb_status() {
    client=${basedir}/bin/mysql
    `${client} --defaults-extra-file=my_ext.cnf -sN -e "show engine innodb status\G"  > innodb_status.log`
}

check_dead_lock() {
    `grep -A9999 "LATEST DETECTED DEADLOCK" innodb_status.log | grep -B9999 "WE ROLL BACK TRANSACTION" > deadlock.log`
    if [ -s "deadlock.log" ]; then
        echo "DEADLOCK exists"
    else
        echo "DEADLOCK doesn't exist"

}



#################################################################
cnf_inavlid_check ${my_cnf}
basedir=$(get_cnf_element 'basedir')
basedir_invalid_check ${basedir}
get_socket
create_extra_cnf my_ext.cnf
export_innodb_status


##################################SQL RESULT##################################

hostname=$(get_sql_result 'select @@hostname')
port=$(get_sql_result 'select @@port')
datadir=$(get_sql_result 'select @@datadir')
binary_log=$(get_sql_result 'select @@innodb_data_home_dir')
error_log=$(get_sql_result 'select @@log_error')
version=$(get_sql_result 'select version()')
slow_query_log=$(get_sql_result 'select @@slow_query_log_file')
data_index_size=$(convert_size $(get_sql_result 'select sum(index_length+data_length) from information_schema.tables'))
schema_of_global_status=$(get_sql_result "select table_schema from information_schema.tables where table_name='global_status'")
innodb_buffer_pool_hit_rate=$(get_sql_result "select round(100-(b.variable_value/(a.variable_value + b.variable_value)) * 100,2)  from ${schema_of_global_status}.global_status a, ${schema_of_global_status}.global_status b where a.variable_name='innodb_buffer_pool_read_requests' and b.variable_name = 'innodb_buffer_pool_reads'")% 
key_buffer_hit_rate=$(is_enabled_key_buffer $(get_sql_result "select round(100-(b.variable_value/(a.variable_value + b.variable_value)) * 100,2)  from ${schema_of_global_status}.global_status a, ${schema_of_global_status}.global_status b where a.variable_name='key_read_requests' and b.variable_name = 'key_reads'"))% 
thread_cache_miss_rate=$(get_sql_result "select round(b.variable_value / a.variable_value * 100,2)  from ${schema_of_global_status}.global_status a, ${schema_of_global_status}.global_status b where a.variable_name='connections' and b.variable_name = 'threads_created'")%
index_usage=$(get_sql_result "select round((100-(((a.variable_value + b.variable_value)/(a.variable_value + b.variable_value + c.variable_value + d.variable_value + e.variable_value + f.variable_value)) * 100)),2) from ${schema_of_global_status}.global_status a, ${schema_of_global_status}.global_status b, ${schema_of_global_status}.global_status c, ${schema_of_global_status}.global_status d, ${schema_of_global_status}.global_status e, ${schema_of_global_status}.global_status f where a.variable_name = 'handler_read_rnd_next'
and b.variable_name = 'handler_read_rnd' and c.variable_name = 'handler_read_first' and d.variable_name = 'handler_read_next' and e.variable_name = 'handler_read_key' and f.variable_name = 'handler_read_prev'")%
max_used_connect=$(get_sql_result "select round(variable_value / @@max_connections, 2) from ${schema_of_global_status}.global_status where variable_name='max_used_connections'")%
aborted_connects=$(get_sql_result "select round((a.variable_value / b.variable_value), 2) * 100 from ${schema_of_global_status}.global_status a, ${schema_of_global_status}.global_status b where a.variable_name='aborted_connects' and b.variable_name='connections'")%
tmp_disk_rate=$(get_sql_result "select round(a.variable_value / (a.variable_value + b.variable_value) * 100,2) from ${schema_of_global_status}.global_status a, ${schema_of_global_status}.global_status b where a.variable_name='created_tmp_disk_tables' and b.variable_name='created_tmp_tables'")%
uptime=$(convert_seconds_to_date $(get_sql_result "select variable_value from ${schema_of_global_status}.global_status where variable_name='uptime'"))
rollback_segment=$(get_sql_result "select count from information_schema.innodb_metrics where name='trx_rseg_history_len'")
qps=$(get_sql_result "select round(a.variable_value / b.variable_value, 2) from ${schema_of_global_status}.global_status a, ${schema_of_global_status}.global_status b where a.variable_name='questions' and b.variable_name='uptime'")
tps=$(get_sql_result "select round((a.variable_value + b.variable_value) / c.variable_value, 2) from ${schema_of_global_status}.global_status a, ${schema_of_global_status}.global_status b, ${schema_of_global_status}.global_status c where a.variable_name='com_commit' and b.variable_name='com_rollback' and c.variable_name='uptime'")
innodb_status=$(check_dead_lock)


##################################OS RESULT##################################
os_ver=$(get_os_ver)
mem_total=$(convert_memory $(get_total_mem) "GB")
cpu_model=$(get_cpu_model)

echo $version $os_ver $hostname $mem_total $cpu_model $port $basedir $datadir $binary_log $error_log $slow_query_log $data_index_size $innodb_buffer_pool_hit_rate $key_buffer_hit_rate $thread_cache_miss_rate $index_usage $max_used_connect $aborted_connects $tmp_disk_rate $uptime $rollback_segment $qps $tps $check_dead_lock
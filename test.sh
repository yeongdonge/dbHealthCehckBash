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

#################################################################
cnf_inavlid_check ${my_cnf}
basedir=$(get_cnf_element 'basedir')
basedir_invalid_check ${basedir}
get_socket
create_extra_cnf my_ext.cnf

version=$(get_sql_result 'select version()')
os_ver=$(get_os_ver)
hostname=$(get_sql_result 'select @@hostname')
mem_total=$(convert_memory $(get_total_mem) "GB")
cpu_model=$(get_cpu_model)
port=$(get_sql_result 'select @@port')
datadir=$(get_sql_result 'select @@datadir')
binary_log=$(get_sql_result 'select @@innodb_data_home_dir')
error_log=$(get_sql_result 'select @@log_error')
slow_query_log=$(get_sql_result 'select @@slow_query_log_file')
data_index_size=$(convert_size $(get_sql_result 'select sum(index_length+data_length) from information_schema.tables'))



echo $version $os_ver $hostname $mem_total $cpu_model $port $basedir $datadir $binary_log $error_log $slow_query_log $data_index_size
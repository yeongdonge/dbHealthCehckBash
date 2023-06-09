#!/bin/bash
#-------------------------------------------------------------


customer="고객사명"
engineer="엔지니어명"
manager="담당자명"
read -p "Enter the DB username : " username
read -sp "Enter the Password : " password
echo
read -p "Enter the my.cnf path (Absolute Path) : " my_cnf
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

echo $version $os_ver $hostname $mem_total $cpu_model $port $basedir
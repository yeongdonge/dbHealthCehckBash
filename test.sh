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
except() {
    echo "   "
    echo "$1"
    echo "Terminated"
    echo "   "
    exit
}

get_basedir() {
    basedir=$(grep "^basedir" ${my_cnf} | awk -F "=" '{print $2}' | tr -d ' ')
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

#################################################################
cnf_inavlid_check ${my_cnf}
get_basedir
basedir_invalid_check ${basedir}
get_socket
create_extra_cnf my_ext.cnf

test=$(get_sql_result 'select version()')

echo ${test}










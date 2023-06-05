#!/bin/sh

#-------------------------------------------------------------
# Input Data
Customer="고객사명"
confirm="점검자" #DBA
manager="담당고객명" #담당자
cycleTime=30 #점검 주기  정수만 기입
user="root" # mysql user
password="1" # mysql password
#--------------------------------------------------------------
#
###########################################
#
#   단위 변환 함수 (KB/MB/GB/TB)
#
###########################################
#
count_cut_parameter=0
cut_parameter () {
cut_parameter=$(printf %.0f $1)
count_cut_parameter=$(($count_cut_parameter+1))

if [ $(($cut_parameter/1024)) -gt 1 ];
then
    cut_parameter $(($cut_parameter/1024))
else
    case $count_cut_parameter in
    1) echo "$cut_parameter byte" ;;
    2) echo "$cut_parameter KB" ;;
    3) echo "$cut_parameter MB" ;;
    4) echo "$cut_parameter GB" ;;
    5) echo "$cut_parameter TB" ;;
    esac
    count_cut_parameter=0;
fi
}
#
###########################################
#
# 오늘 날자 설정 및 사용할 파일명 설정
#
###########################################
#


start_date=`date "+%Y%m%d" -d $cycleTime' day ago'` #  슬로우쿼리, 에러로그 검색 기간에 사용
yyyymmdd_today=`date "+%Y%m%d"` 

html_path=$(pwd)/$yyyymmdd_today.html
outfile_path=$(pwd)/$yyyymmdd_today.out
conf_path=$(pwd)/checkcnf.cnf


#
#############################
#
#      my.cnf 설정
#
#############################
#
# 서버에 기동중인 MySQL의 my.cnf 파일 위치 가져오기
# defaults-file= 값을 기준으로 앞을 모두 공백으로 치환, mysqld_safe 제외
# my.cnf 파일을 읽어서 Slow Log, basedir, socket정보등을 읽어 온다
# 기동된 my.cnf 리스트 를 배열에 담고 유저 입력을 받기 위하여 루프를 돌린다.
#
my_cnfs=(`ps -ef | grep mysqld | grep -vE 'grep|mysqld_safe' | sed -e 's/^.*defaults-file=//' -e 's/^[a-zA-Z0-9].*/default_path/' | awk  '{print $1}'`)


echo -e "\n\n================================"
echo "       choose my.cnf path       "
echo "================================"

PS3=`echo -e "\nPlease select my.cnf: "`
select select_my_cnfs in ${my_cnfs[@]}
do

if [ -n "$select_my_cnfs" ];
then
my_cnf=$select_my_cnfs
break;
else
        echo -e "\nPlease choose the correct number"
fi
done


# 위에서 mysqld 한 결과 --defaults-file 값을 안 물고 있으면 기본 경로의 my.cnf를 사용한다고 판단
# my.cnf 기본 경로이면 아래 수행
if [ default_path == $my_cnf ]
then
# my.cnf 기본 경로 순서
my_cnf_orders=(/etc/my.cnf /etc/mysql/my.cnf /usr/local/mysql/etc/my.cnf ~/.my.cnf)

for j in ${my_cnf_orders[*]}
do
    if [ -e $j ]
    then
        my_cnf=$j
    fi
done

if [ default_path == $my_cnf ]
then
    echo "not found my.cnf file"
fi
fi

echo -e "\nyou selected my.cnf: $my_cnf"


#
#####################################
#
#  Engine 설치 경로 확인 (basedir)
#
# basedir 경로 확인 후 mysql 위치 추가
######################################
#
basedircheck=`echo $(cat $my_cnf | grep -v '^#' | sed 's/#.*//' | grep basedir | tr -d '\t ' | cut -c 9-)`

if [ -z "$basedircheck" ];
then
echo "  "
echo "Must include 'basedir' values in $my_cnf File."
echo "Check please....."
echo "  "
exit 
else
my_client=`echo $(cat $my_cnf | grep -v '^#' | sed 's/#.*//' | grep basedir | tr -d '\t ' | cut -c 9-)/bin/mysql`
fi

my_client=`which mysql`

if [ -z "$my_client" ]
then
    basedircheck=`echo $(cat $my_cnf | grep -v '^#' | sed 's/#.*//' | grep basedir | tr -d '\t ' | cut -c 9-)`
    if [ -z "$basedircheck" ]
    then
        basedircheck="ps -ef | grep mysqld | grep -vE 'grep|mysqld_safe' | sed -e 's/--defaults-file=.*//' | awk '{print $8}'"
        if [[  "$basedircheck" ==  *mysqld* ]]
        then
            my_client="$basedircheck/bin/mysql"
        else
            echo "  "
            echo "Must include 'basedir' values in $my_cnf File."
            echo "Check please....."
            echo "  "
            exit 
        fi
    else
        my_client=`echo $(cat $my_cnf | grep -v '^#' | sed 's/#.*//' | grep basedir | tr -d '\t ' | cut -c 9-)/bin/mysql`
    fi
fi




#
#######################
#
#    Socket 세팅
#
#######################
#
# MySQL 접속 시 소켓통신을 위한 설정
# my.cnf에서 socket 가져오기 (여려개 있을 수 있으므로 NR==1)
# my.cnf 파일에 socket이 지정되어 있지 않으면 기본 경로 인 /tmp/mysql.sock을 사용하도록 설정
#

my_socket=`cat $my_cnf | grep socket | tr -d '\t ' | cut -c 8- | awk 'NR==1'`

if [ -z $my_socket ]
then
my_socket=/tmp/mysql.sock
fi


#
#################################################################
#
# MySQL 접속에 사용할 Config File 생성 및 데이터 잘 들어갔는지 확인
#
#################################################################
# 
# Command Line에서 패스워드를 넣어서 수행하면 워닝 메세지가 나오는데 해당 메세지를 안 나오게 하기 위함
#

echo "
[mysql]
user=\"$user\"
password=\"$password\"
socket=\"$my_socket\"
" > $conf_path


###########################################
#
# MySQL , MariaDB , Percona 정보
#
###########################################
#
full_db_name=$($my_client --defaults-extra-file=$conf_path -e "status;" | grep "Server version" | sed "s/ Server.*$//g" | awk '{print $4 " " $5 }')
db_version=$( $my_client --defaults-extra-file=$conf_path -e "status;" | grep "Server version" | sed "s/ Server.*$//g" | awk '{print $3 }' | sed "s/-.*$//g" )



#schema=$($my_client --defaults-extra-file=$conf_path -e"select table_schema from information_schema.tables where table_name like '%global_status%' and table_schema <> 'sys' ;" | awk  'NR == 2')
schema=$($my_client --defaults-extra-file=$conf_path -e"
select case when cnt = 2 and perf = 1 then 'performance_schema' when cnt = 2 and perf = 0 then 'information_schema' else (select table_schema from information_schema.tables where table_name like '%global_status%' and table_schema <> 'sys') end  
from   (select count(*) cnt , @@performance_schema as perf from  information_schema.tables where table_name like '%global_status%' and table_schema <> 'sys') as main ;
" | awk  'NR == 2')


if [ "$schema" == "information_schema" ]; 
then
    DB_Start_Up=$( $my_client --defaults-extra-file=$conf_path -e"SELECT NOW() - INTERVAL variable_value SECOND MySQL_Started FROM information_schema.global_status WHERE variable_name='Uptime';" | awk 'NR==2' | sed "s/.000000//" )
else
    DB_Start_Up=$( $my_client --defaults-extra-file=$conf_path -e"SELECT NOW() - INTERVAL variable_value SECOND MySQL_Started FROM performance_schema.global_status WHERE variable_name='Uptime';" | awk 'NR==2' | sed "s/.000000//" )
fi







db_engine=$($my_client --defaults-extra-file=$conf_path -e"show variables like 'default_storage_engine';" | awk  'NR == 2  {print $2}' )
character=$( $my_client --defaults-extra-file=$conf_path -e"show variables like 'character_set_server';"  | awk  'NR == 2  {print $2 }')
isolation=$( $my_client --defaults-extra-file=$conf_path -e"show variables like '%isolation%';" | awk  'NR == 2  {print $2 }' )

performance_schema=$( $my_client --defaults-extra-file=$conf_path -e"show variables like 'performance_schema';" | awk  'NR == 2  {print $2 }'  )

#
#########################################################################
#
#   Server 구성 확인 (StandAlone/Master/Multi-master/Chain-slave/Slave)
#
#########################################################################
#
# 서버 상태 파악은 show slave status , show processlist에서 slave process가 접속해 있는지 여부, Read Only 여부를 가지고 판단 함
#


# read only
read_only_status=$($my_client --defaults-extra-file=$conf_path -e"SELECT @@read_only" | awk 'NR==2')

# show slave status
Slave_IO_Running=$($my_client --defaults-extra-file=$conf_path -e"show slave status \G" | grep 'Slave_IO_Running:' | awk  '{print $2 }')

# slave process check
figure_M_S=$($my_client --defaults-extra-file=$conf_path -e "SELECT STATE  FROM information_schema.processlist WHERE STATE LIKE '%has sent all binlog%';" | awk 'NR==2')

if [ -n "$figure_M_S" ] && [ -n "$Slave_IO_Running" ] 
then

if [ 0 -eq "$read_only_status" ] 
then
    server_state="MULTI_MASTER"
else                            
    server_state="CHAIN SLAVE"
fi

else

if [ -n "$figure_M_S" ] 
then
    server_state="MASTER"
elif [ -n "$Slave_IO_Running" ] 
then
    server_state="SLAVE"
else
    server_state="STANDALONE"
fi

fi

if [ 0 -eq "$read_only_status" ] 
then
  read_only_status="OFF"
else
  read_only_status="ON"
fi

#
###########################################
#
# Replication Info 
#
###########################################
#

master_host=$( $my_client --defaults-extra-file=$conf_path -e"show slave status \G  " | grep 'Master_Host:' | awk  '{print $2}' )
Slave_SQL_Running=$($my_client --defaults-extra-file=$conf_path -e"show slave status \G" | grep 'Slave_SQL_Running:' | awk  '{print $2 }')
Slave_Source_Log_File=$($my_client --defaults-extra-file=$conf_path -e"show slave status \G" | grep 'Master_Log_File:' | grep -v 'Relay_Master_Log_File:' | awk  '{print $2 }')
Slave_Read_Source_Log_Pos=$($my_client --defaults-extra-file=$conf_path -e"show slave status \G" | grep 'Read_Master_Log_Pos:' | awk  '{print $2 }')
Seconds_Behind_Master=$($my_client --defaults-extra-file=$conf_path -e"show slave status \G" | grep 'Seconds_Behind_Master' | awk  '{print $2 }')


# Slave값이 없을 경우 빈 괄호 출력 안함
if [ -n "$Slave_IO_Running" ];
then
Slave_Log_File_Pos="$Slave_Source_Log_File ($Slave_Read_Source_Log_Pos)"
else
Slave_Log_File_Pos=" "
fi

if [ -n "$Slave_SQL_Running" ];
then
Slave_IO_Running="${Slave_SQL_Running} / ${Slave_IO_Running}"
else
Slave_IO_Running="  "
fi




#
# O/S
#
os_ver=$(  cat /etc/*release* | tail -3 | head -1  | sed -e 's/(.*//' -e 's/^.*\"//' -e 's/Linux//' -e 's/Server//' -e 's/   / /' -e 's/release//' -e 's/  //' -e 's/Enterprise//' )
cpu=$( cat /proc/cpuinfo | grep processor | wc -l )
os_memory=$(free -h | grep "Mem" | awk  '{print $2}')
host_name=$(hostname)
if_config=$( ip addr | grep global | awk  '{print $2}' | cut -d/ -f1 | tr "\n" " : " )
os_uptime=$( uptime -s)


#
# InnoDB
#

innodb_bf_size_decimal=$( $my_client --defaults-extra-file=$conf_path -e"select @@innodb_buffer_pool_size ;"  | awk 'NR==2'  )
innodb_bf_size=$( cut_parameter $innodb_bf_size_decimal )

#
# Global waits
#

global_wait=`$my_client --defaults-extra-file=$conf_path -e"select performance_schema.events_waits_summary_global_by_event_name.EVENT_NAME AS event,
    performance_schema.events_waits_summary_global_by_event_name.COUNT_STAR AS total,
    -- (performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT) 
    CASE WHEN  performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT IS NULL THEN  NULL
    WHEN performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT >= 604800000000000000 THEN  CONCAT(ROUND(performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT / 604800000000000000, 2), ' w')
    WHEN performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT >= 86400000000000000 THEN  CONCAT(ROUND(performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT / 86400000000000000, 2), ' d')
    WHEN performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT >= 3600000000000000 THEN  CONCAT(ROUND(performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT / 3600000000000000, 2), ' h')
    WHEN performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT >= 60000000000000 THEN  CONCAT(ROUND(performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT / 60000000000000, 2), ' m')
    WHEN performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT >= 1000000000000 THEN  CONCAT(ROUND(performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT / 1000000000000, 2), ' s')
    WHEN performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT >= 1000000000 THEN  CONCAT(ROUND(performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT / 1000000000, 2), ' ms')
    WHEN performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT >= 1000000 THEN  CONCAT(ROUND(performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT / 1000000, 2), ' us')
    WHEN performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT >= 1000 THEN  CONCAT(ROUND(performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT / 1000, 2), ' ns')
    ELSE  CONCAT(performance_schema.events_waits_summary_global_by_event_name.AVG_TIMER_WAIT, ' ps')
    END    AS avg_latency
    from performance_schema.events_waits_summary_global_by_event_name 
    where ((performance_schema.events_waits_summary_global_by_event_name.EVENT_NAME <> 'idle') 
    and (performance_schema.events_waits_summary_global_by_event_name.SUM_TIMER_WAIT > 0)) 
    order by performance_schema.events_waits_summary_global_by_event_name.SUM_TIMER_WAIT desc limit 5 ;" | grep -v total`
global_event_1=`echo $global_wait | awk  '{print $1}'`
global_event_2=`echo $global_wait | awk  '{print $5}'`
global_event_3=`echo $global_wait | awk  '{print $9}'`
global_event_4=`echo $global_wait | awk  '{print $13}'`
global_event_5=`echo $global_wait | awk  '{print $17}'`
global_total_1=`echo $global_wait | awk  '{print $2}'`
global_total_2=`echo $global_wait | awk  '{print $6}'`
global_total_3=`echo $global_wait | awk  '{print $10}'`
global_total_4=`echo $global_wait | awk  '{print $14}'`
global_total_5=`echo $global_wait | awk  '{print $18}'`
global_avg_1=`echo $global_wait | awk  '{print $3, $4}'`
global_avg_2=`echo $global_wait | awk  '{print $7, $8}'`
global_avg_3=`echo $global_wait | awk  '{print $11, $12}'`
global_avg_4=`echo $global_wait | awk  '{print $15, $16}'`
global_avg_5=`echo $global_wait | awk  '{print $19, $20}'`

#
# Slow Query
#

slow_query_exict=$($my_client --defaults-extra-file=$conf_path -e"show variables like 'slow_query_log'" | awk  'NR == 2  {print $2 }')

if [ "$slow_query_exict" == "ON" ]  # 슬로우쿼리 존재 여부 체크. 없으면 건너뜀
then
slow_query=$( $my_client --defaults-extra-file=$conf_path -e"status;" | grep -i Queries | cut -d ":" -f8 | tr -d ' ' )

slow_log_path=`$my_client --defaults-extra-file=$conf_path -e"show variables like 'slow_query_log_file'" | grep 'slow_query' | awk  '{print $2 }'`
slow_second_time=`$my_client --defaults-extra-file=$conf_path -e"show variables like 'long_query_time'" | grep 'long_query_time' | awk  '{print $2 }'`
slow_second=$(printf %.1f "$slow_second_time") #slow second 소수점 1자리 고정

start_point=`grep '# Time: ' $slow_log_path | cut -c 9-18 | sed 's/\-//g' | awk  '$1 >= '$start_date | head -n 1 | sed -e 's/./&-/4' -e 's/..$/-&/'`
if [ -z "$start_point" ] ; then
    slow_query_count=0        
else
    start_line=`grep -En $start_point $slow_log_path | head -1 | awk  '{print $1}' | sed 's/\:.*//'`
    slow_query_count=$(sed -n "$start_line, \$p" $slow_log_path | grep Query_time | awk  '$3>='$slow_second'{print $3}' | wc -l)        
fi
else
slow_query_count="-"
slow_second="-"
fi

#
# Objects Size
#

data_size_full=$( $my_client --defaults-extra-file=$conf_path -e"SELECT ROUND(SUM(data_length) , 2) AS 'Size in (MB)' FROM information_schema.TABLES;" | awk  'NR==2' )
data_size=$( cut_parameter $data_size_full) #slow second 소수점 3자리 고정

index_size_full=$( $my_client --defaults-extra-file=$conf_path -e"SELECT ROUND(SUM(index_length) , 2) AS 'Size in (MB)' FROM information_schema.TABLES;" | awk  'NR==2' )
index_size=$( cut_parameter $index_size_full) #slow second 소수점 3자리 고정

user_data_size=$( $my_client --defaults-extra-file=$conf_path -e"select concat( engine , ' ' ,  ROUND(SUM(data_length) / 1024 / 1024, 2) , ' / ' ,  ROUND(SUM(index_length) / 1024 / 1024, 2) ,'<br>' )   from  information_schema.TABLES  where table_schema not in ('performance_schema' , 'information_schema', 'sys' ,'mysql' )  and ENGINE is not NULL group by ENGINE ;" | awk  'NR>=2' )

#
# Objects Count
#

database_cnt=$($my_client --defaults-extra-file=$conf_path -e "select count(*) from (select  distinct table_schema from information_schema.tables where table_schema not in ('performance_schema' , 'information_schema', 'sys' ,'mysql' )) a;" | awk 'NR==2')
table_cnt=$( $my_client --defaults-extra-file=$conf_path -e"select count(*) as 'Table_CNT' from information_schema.TABLES where table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys');" | awk  'NR==2')
index_cnt=$( $my_client --defaults-extra-file=$conf_path -e"select count(index_name) as 'Index_CNT' from information_schema.STATISTICS where table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys');" | awk  'NR==2' )
unused_index_cnt=$( $my_client --defaults-extra-file=$conf_path -e"SELECT count(INDEX_NAME) as 'Unused Index_CNT' FROM performance_schema.table_io_waits_summary_by_index_usage WHERE INDEX_NAME IS NOT NULL AND COUNT_STAR = 0 AND OBJECT_SCHEMA <> 'mysql' ORDER BY OBJECT_SCHEMA,OBJECT_NAME;" | awk  'NR==2' )
view_cnt=$( $my_client --defaults-extra-file=$conf_path -e"SELECT count(table_name) AS 'View_CNT' FROM information_schema.views WHERE table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys');" | awk  'NR==2')
procedure_cnt=$( $my_client --defaults-extra-file=$conf_path -e"select count(*) as 'Procedure_CNT' from information_schema.routines where ROUTINE_TYPE = 'PROCEDURE' and ROUTINE_SCHEMA not in ('information_schema', 'mysql', 'performance_schema', 'sys');"  | awk  'NR==2' )
function_cnt=$( $my_client  --defaults-extra-file=$conf_path -e"select count(*) as 'Function_CNT' from information_schema.routines where ROUTINE_TYPE = 'FUNCTION' and ROUTINE_SCHEMA not in ('information_schema', 'mysql', 'performance_schema', 'sys');"  | awk  'NR==2' )
trigger_cnt=$( $my_client --defaults-extra-file=$conf_path -e"SELECT count(trigger_name) as 'Trigger_CNT' FROM information_schema.triggers WHERE trigger_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys');" | awk  'NR==2' )

#
# Data Directory O/S Usage
#

datadir=$( $my_client --defaults-extra-file=$conf_path -e"show variables like 'datadir';" | awk  'NR==2  {print $2} ' )

finddir=$datadir
cutdir=""

# datadir의 제일 마지막에 /가 붙어 있는지 체크 후 붙어 있으면 제거
check_last=`echo ${finddir:(-1)}`
if [ "$check_last" == "/" ] 
then

finddir=`echo $finddir | sed 's/.\{1\}$//g'`  # 마지막 1문자 제거 (/)
fi

# 뒤에서 부터 하나 하나 줄여 가면서 체크
while true
do
find_df=`df -h | grep "$finddir$"`

if [ "$find_df" == "" ] 
then
    cutdir=${finddir##*/} #뒤에서 부터 /를 찾아서 그 뒤의 문자 반환.  

    # 찾은 문자와 앞에 / 를 붙여서 지움
    finddir=`echo $finddir | sed "s/\/$cutdir.*$//g"`
else
    break
fi
if [ "$finddir" == "" ] 
    then
        find_df=`df -h | grep "/$"`
        break
fi
done

dfSize=$(echo $find_df | awk  '{print $2}' )
dfAvail=$(echo $find_df  | awk  '{print $4}' )
dfUse=$(echo $find_df  | awk  '{print $5}' )
Mounted=$(echo $find_df  | awk  '{print $6}' )
dfUse_size=$(echo $find_df  | awk  '{print $3}' )

#
#  Redo log
#
redo_buffer_size_decimal=$( $my_client --defaults-extra-file=$conf_path -e"select @@innodb_log_buffer_size ;"   | awk  'NR==2'   )
redo_buffer_size=$( cut_parameter $redo_buffer_size_decimal)

trx_commit=$( $my_client --defaults-extra-file=$conf_path -e"show variables like 'innodb_flush_log_at_trx_commit';" | awk  'NR==2  {print $2}')

innodb_log_file_size_decimal=$( $my_client --defaults-extra-file=$conf_path -e"select @@innodb_log_file_size ;"  | awk  'NR==2'  )
innodb_log_file_size=$( cut_parameter $innodb_log_file_size_decimal)

innodb_log_files_in_group=$( $my_client --defaults-extra-file=$conf_path -e"show variables like 'innodb_log_files_in_group';" | awk  'NR==2  {print $2}' )

#
# Binary log
#

binlog_cache_size_decimal=$( $my_client --defaults-extra-file=$conf_path -e"select @@binlog_cache_size ;"  | awk  'NR==2'  )
binlog_cache_size=$( cut_parameter $binlog_cache_size_decimal)

expire_logs_days=$( $my_client --defaults-extra-file=$conf_path -e"show variables like 'expire_logs_days';"  | awk  'NR==2  {print $2}' )

master_status_file=$( $my_client --defaults-extra-file=$conf_path -e"show master status \G" | grep 'File' | awk  '{print $2}' )
master_status_position=$( $my_client --defaults-extra-file=$conf_path -e"show master status \G" | grep 'Position' | awk  '{print $2}' )


#
# Connection
#

socket_info=$( $my_client --defaults-extra-file=$conf_path -e"show variables like 'socket';" | awk  'NR==2  {print $2}' )
port_info=$( $my_client --defaults-extra-file=$conf_path -e"show variables like 'port';" | awk  'NR==2  {print $2}' )

max_connections=$($my_client --defaults-extra-file=$conf_path -e"show variables like 'max_connections';"  | awk  'NR==2  {print $2}' )
Max_used_connections=$( $my_client --defaults-extra-file=$conf_path -e"show status like 'Max_used_connections';" | awk  'NR==2  {print $2}' )
Connections=$($my_client --defaults-extra-file=$conf_path -e"show status like 'Connections';"  | awk  'NR==2  {print $2}' )

Threads_connected=$($my_client --defaults-extra-file=$conf_path -e"show status like 'Threads_connected';"  | awk  'NR==2  {print $2}' )
Threads_created=$($my_client --defaults-extra-file=$conf_path -e"show status like 'Threads_created';" | awk  'NR==2  {print $2}' )
Threads_running=$($my_client   --defaults-extra-file=$conf_path -e"show status like 'Threads_running';"  | awk  'NR==2  {print $2}' )

Process_Status1=$($my_client   --defaults-extra-file=$conf_path -e"select id, user, host, db, command, time, state from information_schema.processlist where user not in ('system user' ,'event_scheduler' ) AND command not in ( 'Binlog Dump' , 'Sleep') order by time desc limit 2;" | awk  'NR==2')
Process_Status2=$($my_client   --defaults-extra-file=$conf_path -e"select id, user, host, db, command, time, state from information_schema.processlist where user not in ('system user' ,'event_scheduler' ) AND command not in ( 'Binlog Dump' , 'Sleep') order by time desc limit 2;" | awk  'NR==3')

PS_id1=`echo $Process_Status1 | awk  '{print $1}'`
PS_user1=`echo $Process_Status1 | awk  '{print $2}'`
PS_host1=`echo $Process_Status1 | awk  '{print $3}'`
PS_db1=`echo $Process_Status1 | awk  '{print $4}'`
PS_cmd1=`echo $Process_Status1 | awk  '{print $5}'`
PS_time1=`echo $Process_Status1 | awk  '{print $6}'`

PS_id2=`echo $Process_Status2 | awk  '{print $1}'`
PS_user2=`echo $Process_Status2 | awk  '{print $2}'`
PS_host2=`echo $Process_Status2 | awk  '{print $3}'`
PS_db2=`echo $Process_Status2 | awk  '{print $4}'`
PS_cmd2=`echo $Process_Status2 | awk  '{print $5}'`
PS_time2=`echo $Process_Status2 | awk  '{print $6}'`


#
# Error
#

error_path=$( $my_client --defaults-extra-file=$conf_path -e"show variables like 'log_error'" | awk  'NR==2  {print $2}' )
error_start_point=`cat $error_path | cut -c 1-10 | sed 's/\-//g' | grep '\<[0-9]\{8\}\>' | awk  '$1 >= '$start_date | head -1 | sed -e 's/./&-/4' -e 's/..$/-&/'`

if [ -z ${error_start_point} ]  
then
Error_Msg=''
Warnings_Msg=''
else
error_start_line=`grep -En $error_start_point $error_path | head -1 | awk  '{print $1}' | sed 's/\:.*//'`
Error_Msg=$(sed -n "$error_start_line, \$p" $error_path | grep "\[ERROR\]" | tail -1)
Warnings_Msg=$(sed -n "$error_start_line, \$p" $error_path | grep "\[Warning\]" | tail -1)
fi


#
# Average Query time Sec
#

avg_query_time=$($my_client --defaults-extra-file=$conf_path -e"status;" | grep -i Queries | cut -d ":" -f8 | tr -d ' ')

#
# For output file - user data size
#

user_data_size_out=$( $my_client --defaults-extra-file=$conf_path -e"select concat( '                ' , engine , ' : ' ,  ROUND(SUM(data_length) / 1024 / 1024, 2) , ' / ' ,  ROUND(SUM(index_length) / 1024 / 1024, 2) )   from  information_schema.TABLES  where table_schema not in ('performance_schema' , 'information_schema', 'sys' ,'mysql' )  and ENGINE is not NULL group by ENGINE ;" | awk  'NR>=2' )

top_session_10=$($my_client --defaults-extra-file=$conf_path -e "SELECT '        ' , id , user  , db , time , substr(info , 1, 50)   FROM information_schema.processlist WHERE  user not in ('system user' ,'event_scheduler' ) AND command not in ( 'Binlog Dump' , 'Sleep') ANd time > 60 ORDER BY time desc limit 10 ;" | awk 'NR>=2')

if [ -z ${top_session_10} ]  
then
top_session_10="            No rows over 60 sec....."
fi


#
################################################
#
#  테이블 상세 정보
#
################################################
#
#테스트 코드
#all_list=$(/engine/mysql/enter8.0/bin/mysql -uroot -p1 -S /data/mysql/enter8.0/mysql.sock -e" SELECT \`SCHEMA\`, \`TYPE\`, \`COUNT\`, \`SIZE\`  FROM ( select TABLE_SCHEMA as \`SCHEMA\`, CASE WHEN ENGINE IS NULL THEN 2 ELSE 1 END AS Seq, CASE WHEN ENGINE IS NULL THEN 'VIEW' ELSE CONCAT( 'TABLE', '=', engine) END as \`TYPE\`, count(*) as COUNT, ROUND(SUM(data_length) , 2) as SIZE from information_schema.tables where table_schema not in ('information_schema','performance_schema','sys','mysql') group by table_schema, engine union all select INDEX_SCHEMA,  3,  'INDEX',  count(*),  (select ROUND(SUM(index_length) , 2)  from information_schema.tables b  where b.table_schema=a.INDEX_SCHEMA)   from information_schema.STATISTICS a  where table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')  group by INDEX_SCHEMA union all select ROUTINE_SCHEMA,  4,  ROUTINE_TYPE,  count(*),  0  from information_schema.routines  where ROUTINE_SCHEMA not in ('information_schema', 'mysql', 'performance_schema', 'sys')  group by ROUTINE_SCHEMA, ROUTINE_TYPE union all select TRIGGER_SCHEMA, 5,  'TRIGGER',  count(*),  0  from information_schema.triggers  WHERE trigger_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')  group by TRIGGER_SCHEMA  ) main ORDER BY \`SCHEMA\`, seq, \`TYPE\`; " )
#engine_line_list=$(/engine/mysql/enter8.0/bin/mysql -uroot -p1 -S /data/mysql/enter8.0/mysql.sock -e" SELECT \`SCHEMA\`, \`TYPE\`, \`COUNT\`, \`SIZE\`  FROM ( select TABLE_SCHEMA as \`SCHEMA\`, CASE WHEN ENGINE IS NULL THEN 2 ELSE 1 END AS Seq, CASE WHEN ENGINE IS NULL THEN 'VIEW' ELSE CONCAT( 'TABLE', '=', engine) END as \`TYPE\`, count(*) as COUNT, ROUND(SUM(data_length) , 2) as SIZE from information_schema.tables where table_schema not in ('information_schema','performance_schema','sys','mysql') group by table_schema, engine union all select INDEX_SCHEMA,  3,  'INDEX',  count(*),  (select ROUND(SUM(index_length) , 2)  from information_schema.tables b  where b.table_schema=a.INDEX_SCHEMA)   from information_schema.STATISTICS a  where table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')  group by INDEX_SCHEMA union all select ROUTINE_SCHEMA,  4,  ROUTINE_TYPE,  count(*),  0  from information_schema.routines  where ROUTINE_SCHEMA not in ('information_schema', 'mysql', 'performance_schema', 'sys')  group by ROUTINE_SCHEMA, ROUTINE_TYPE union all select TRIGGER_SCHEMA, 5,  'TRIGGER',  count(*),  0  from information_schema.triggers  WHERE trigger_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')  group by TRIGGER_SCHEMA  ) main ORDER BY \`SCHEMA\`, seq, \`TYPE\`; " |  awk '{print $1}')

all_list=$($my_client --defaults-extra-file=$conf_path -e" 
SELECT \`SCHEMA\`, \`TYPE\`, \`COUNT\`, \`SIZE\`  
FROM ( select TABLE_SCHEMA as \`SCHEMA\`, CASE WHEN ENGINE IS NULL THEN 2 ELSE 1 END AS Seq, CASE WHEN ENGINE IS NULL THEN 'VIEW' ELSE CONCAT( 'TABLE', '=', engine) END as \`TYPE\`, count(*) as COUNT, ROUND(SUM(data_length) , 2) as SIZE 
       from information_schema.tables 
       where table_schema not in ('information_schema','performance_schema','sys','mysql') group by table_schema, engine 
       union all 
       select a.table_schema , '3' , 'INDEX' , a.cnt , b.sm
       from  ( select table_SCHEMA, count(*) as cnt from information_schema.STATISTICS where table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')  group by table_SCHEMA ) a ,
             ( select table_schema , ROUND(SUM(index_length) , 2) as sm from information_schema.tables where table_schema not in ('information_schema','performance_schema','sys','mysql') group by table_schema ) b
       where  a.table_schema = b.table_schema 
       union all 
       select ROUTINE_SCHEMA,  4,  ROUTINE_TYPE,  count(*),  0  
       from information_schema.routines  
       where ROUTINE_SCHEMA not in ('information_schema', 'mysql', 'performance_schema', 'sys')  group by ROUTINE_SCHEMA, ROUTINE_TYPE 
       union all 
       select TRIGGER_SCHEMA, 5,  'TRIGGER',  count(*),  0  
       from information_schema.triggers  
       WHERE trigger_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')  group by TRIGGER_SCHEMA  
      ) main 
ORDER BY \`SCHEMA\`, seq, \`TYPE\`; " )




engine_line_list=$($my_client --defaults-extra-file=$conf_path -e" 
SELECT \`SCHEMA\`, \`TYPE\`, \`COUNT\`, \`SIZE\`  
FROM ( select TABLE_SCHEMA as \`SCHEMA\`, CASE WHEN ENGINE IS NULL THEN 2 ELSE 1 END AS Seq, CASE WHEN ENGINE IS NULL THEN 'VIEW' ELSE CONCAT( 'TABLE', '=', engine) END as \`TYPE\`, count(*) as COUNT, ROUND(SUM(data_length) , 2) as SIZE 
       from information_schema.tables 
       where table_schema not in ('information_schema','performance_schema','sys','mysql') group by table_schema, engine 
       union all 
       select a.table_schema , '3' , 'INDEX' , a.cnt , b.sm
       from  ( select table_SCHEMA, count(*) as cnt from information_schema.STATISTICS where table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')  group by table_SCHEMA ) a ,
             ( select table_schema , ROUND(SUM(index_length) , 2) as sm from information_schema.tables where table_schema not in ('information_schema','performance_schema','sys','mysql') group by table_schema ) b
       where  a.table_schema = b.table_schema 
       union all 
       select ROUTINE_SCHEMA,  4,  ROUTINE_TYPE,  count(*),  0  
       from information_schema.routines  
       where ROUTINE_SCHEMA not in ('information_schema', 'mysql', 'performance_schema', 'sys')  group by ROUTINE_SCHEMA, ROUTINE_TYPE 
       union all 
       select TRIGGER_SCHEMA, 5,  'TRIGGER',  count(*),  0  
       from information_schema.triggers  
       WHERE trigger_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')  group by TRIGGER_SCHEMA  
      ) main 
ORDER BY \`SCHEMA\`, seq, \`TYPE\`; " |  awk '{print $1}')

engine_length=0;
engine_count=0;
skip_engine_length=2

# 먼저 테이블의 개수 파악
avc=`echo $engine_line_list | cut -d ' ' -f2`
engine_db_list=(`echo $engine_line_list | cut -d ' ' -f2`)

while [ -n "${engine_db_list[ $engine_length ]}" ] 
do
((engine_length++))
((skip_engine_length++))
engine_db_list+=(`echo $engine_line_list | cut -d ' ' -f$skip_engine_length` )
done


for (( t=0; t<${#engine_db_list[*]}; t++ ))
do
    t_secound=$((t+1))
    if [ "${engine_db_list[ $t ]}" != "${engine_db_list[ $t_secound ]}" ]; then
    {
        engine_profile+=(${engine_db_list[ $t ]});
        t_engine_count=$((engine_count+1))
        engine_profile+=($t_engine_count)
        engine_count=0;
    }
    elif [ "${engine_db_list[ $t ]}" == "${engine_db_list[ $t_secound ]}" ]; then
    {
        ((engine_count++))
    }
    elif [ -z "${engine_db_list[ $t_secound ]}" ]; then
    {
        engine_profile+=("${engine_db_list[ $t ]}");
        engine_profile+=($engine_count)
    }
    else
    {
        echo " 버그"
    }
    fi
done
echo " "
# engine_db_list=( aaa ,3 , bbb , 6 , ccc , 2) 이런 형식으로 저장됨
# aaa에 관련정보 3개 bbb에 관련정보 6개 ccc는 2개란 뜻이다.






#
############################################
#
# Make HTML
#
############################################
#



echo "
<!Doctype html>
<html>
<head>
<meta charset='utf-8'>
<meta http-equiv='Content-Type' content='text/html; charset=utf-8' />
<style>
#orange {background-color: rgb(233, 181, 122)}
#grey {background-color: rgb(207, 206, 206); text-align: left;}
table{ border-bottom: none; border-spacing: 0px; padding: 0px;margin: 0 auto;width: 100%; border: 2px solid black; border-collapse: collapse; }
td,th {border: 2px solid black; border-spacing: 0px; border-bottom: none  ;height:16px ;font-size: xx-small; }
#small_title { border: 2px solid black;border-bottom: none ;font-size: 16px;width: 50%;background-color: rgb(233, 181, 122);display: block;margin-top: 16px;}
#last1{padding-left: 10px;border: 1px;}
#last2{border: 1px;border-bottom: 1px solid black;}
#left{ padding-left: 10px; margin: o  auto; text-align:left; font-size: small; font-weight: bold;}
@page {size: auto;margin: 0;}
#blockin{text-align: left; border-top: none}
#grey_center{background-color: rgb(207, 206, 206); text-align: center;}
</style>
</head>

<body style='width: 210mm;  min-height: 297mm; margin: 0 auto;padding: 30px;  border-collapse: collapse;'>
<top>
<title_top style='text-align:center;'>
    <p style='font-size: 24px;  margin: 0 auto; font-weight: 1000; '>MYSQL SERVICE REPORT</p>
    <div style=' width: 400px ; line-height: 1; border-bottom: double 7px black; margin: 0 auto; padding-top: 7px;'></div>
    <p id='left'> ▣ SITE : $Customer
</title_top>
<scema >
   <table style='text-align:center;'>
        <th id='orange' colspan='2'>SERVICE</th>
        <th id='orange' colspan='4'>WARRANTY: $warranty_value</th>
        <th id='orange' colspan='3'>M/A: $ma_value </th>
        <tr>
            <td rowspan='2'  style='font-weight: bold;'>OS</td>
            <td id='grey_center'>OS ver</td>
            <td id='grey_center'>CPU</td>
            <td id='grey_center'>Memory</td>
            <td id='grey_center'>Hostname</td>
            <td id='grey_center'>Replication</td>
            <td id='grey_center' colspan='2' >IP</td>
            <td id='grey_center'>OS Startup</td>
        </tr>
        <tr>
            <td >$os_ver</td>
            <td >$cpu</td>
            <td >$os_memory</td>
            <td >$host_name</td>
            <td >$server_state</td>
            <td colspan='2' >$if_config</td>
            <td >$os_uptime</td>
        </tr>
        <tr>
            <td rowspan='2' style='font-weight: bold;'>DBMS</td>
            <td id='grey_center'>$full_db_name</td>
            <td id='grey_center'>Engine</td>
            <td id='grey_center'>Character</td>
            <td id='grey_center'>bufferpool size</td>
            <td id='grey_center'>Tx_Isolation </td>
            <td id='grey_center'>Performance Schema</td>
            <td id='grey_center'> Read Only </td>
            <td id='grey_center'>DB startup</td>
        </tr>
        <tr>
            <td>$db_version</td>
            <td>$db_engine</td>
            <td>$character</td>
            <td>$innodb_bf_size</td>
            <td>$isolation</td>
            <td>$performance_schema</td>
            <td>$read_only_status</td>
            <td>$DB_Start_Up    </td>
        </tr>
    </table>
</scema>
</top>

<medium>
<small_title id='small_title'> ▣ MYSQL STATUS SUMMARY
</small_title>
<table  style='text-align:center;' >
    <th id='grey' style='text-align: center; font-size: small;'>Check List</th>
    <th id='grey' style='text-align: center; font-size: small;' colspan='12'>Server Contents</th>
    <th id='grey' style='text-align: center; font-size: small;'>Results</th>
    
    <Global_Wait>
        <tr>
            <td rowspan='6' id='left'> ■ Global Wait</td>
            <td id='grey' colspan='6'style='text-align: center;'> Events</td>
            <td id='grey_center' colspan='3'> Total(count)</td>
            <td id='grey_center' colspan='3'> Avg Latency</td>
            <td rowspan='6' style='width: 120px;'>OK</td>
        </tr>
        <tr>
            <td colspan='6' style='text-align: left;'>$global_event_1</td>
            <td colspan='3'>$global_total_1</td>
            <td style='text-align: right;' colspan='3'>$global_avg_1</td>
        </tr>
        <tr>
            <td colspan='6' style='text-align: left;'>$global_event_2</td>
            <td colspan='3'>$global_total_2</td>
            <td colspan='3' style='text-align: right;'>$global_avg_2</td>
        </tr>
        <tr>
            <td colspan='6' style='text-align: left;'>$global_event_3</td>
            <td colspan='3'>$global_total_3</td>
            <td colspan='3' style='text-align: right;'>$global_avg_3</td>
        </tr>
        <tr>
            <td colspan='6' style='text-align: left;'>$global_event_4</td>
            <td colspan='3'>$global_total_4</td>
            <td colspan='3' style='text-align: right;'>$global_avg_4</td>
        </tr>
        <tr>
            <td colspan='6' style='text-align: left;'>$global_event_5</td>
            <td colspan='3'>$global_total_5</td>
            <td colspan='3' style='text-align: right;'>$global_avg_5</td>
        </tr>
    </Global_Wait>

    <Slow_Query>
        <tr>
            <td rowspan='2' id='left'> ■ Slow Query</td>
            <td id='grey' colspan='6'> Queries per second avg (s)</td>
            <td colspan='6'>$slow_query</td>
            <td rowspan='2'>OK</td>
        </tr>
        <tr>
            <td id='grey' colspan='6'> Count & Set Time (s)</td>
            <td colspan='3' >$slow_query_count</td>
            <td colspan='3' >$slow_second  </td>
        </tr>
    </Slow_Query>

    <Segment_Info>
        <tr>
            <td rowspan='2' id='left' > ■ Segment Info</td>
            <td id='grey' colspan='6' style='text-align: center;'> Total Size  [ Data / Index ]</td>
            <td id='grey' colspan='6' style='text-align: center;'> User Data Size  [ Data / Index (MB) ]</td>
            <td rowspan='2'>OK</td>
        </tr>
        <tr>
            <td colspan='6' style='border-bottom: 2px black solid;'>$data_size / $index_size</td>
            <td colspan='6' style='border-bottom: 2px black solid;'>$user_data_size </td>
        </tr>
    </Segment_Info>

    <Object_Info>
        <tr>
            <td rowspan='4' id='left' > ■ Object Info</td>
            <td  colspan='6' id='blockin' > ▪ Database: $database_cnt</td>
            <td  colspan='6' id='blockin' > ▪ View : $view_cnt</td>
            <td rowspan='4' >OK</td>
        </tr>
        <tr>
            <td  colspan='6' id='blockin' > ▪ Table: $table_cnt</td>
            <td  colspan='6' id='blockin' > ▪ Procedure : $procedure_cnt</td>
        </tr>
        <tr>
            <td  colspan='6' id='blockin' > ▪ Index : $index_cnt</td>
            <td  colspan='6' id='blockin' > ▪ Function : $function_cnt</td>
        </tr>
        <tr>
            <td colspan='6' id='blockin' > ▪ Unused Index : $unused_index_cnt</td>
            <td colspan='6' id='blockin' > ▪ Trigger : $trigger_cnt</td>
        </tr>
    </Object_Info>

    <Data_File_Status>
        <tr>
            <td rowspan='3' id='left' > ■ Data File Status</td>
            <td id='grey' colspan='6' style='text-align:center' >  Path</td>
            <td id='grey' colspan='6' style='text-align:center'>  OS F/S Usage (%)</td>
            <td rowspan='3'>OK</td>
        </tr>
        <tr>
            <td colspan='6' rowspan='2' > $datadir </td>
            <td colspan='4' style='text-align: left; border-right: none;'> ▪ Mounted on: ( $Mounted )  </td>
            <td colspan='2' style='text-align: left;  border-left: none;'> ▪ Size : $dfSize </td>
        </tr>
        <tr>
            <td colspan='4' id='blockin' style='border-right: none;'> ▪ Used : $dfUse_size ($dfUse)  </td>
            <td colspan='2' id='blockin' style='border-left: none;'>  ▪ Avail : $dfAvail </td>
        </tr>
    </Data_File_Status>

    <Replication_Status>
        <tr>
            <td rowspan='2'  id='left' > ■ Replication Status</td>
            <td id='grey_center' colspan='3' style=' text-align: center;'>  Master Server</td>
            <td id='grey_center' colspan='3' style='text-align: center;'>  Master Log (position) </td>
            <td id='grey_center' colspan='3' style=' text-align: center;'>  SQL/IO running </td>
            <td id='grey_center' colspan='3' style=' text-align: center;'>  Seconds Behind Master</td>
            <td rowspan='2'>OK</td>
        </tr>
        <tr>
            <td colspan='3'> $master_host</td>
            <td colspan='3'> $Slave_Log_File_Pos</td>
            <td colspan='3'> $Slave_IO_Running </td>
            <td colspan='3'> $Seconds_Behind_Master</td>
        </tr>
    </Replication_Status>

    <Redo_log_Info>
        <tr>
            <td rowspan='2' id='left' > ■ Redo log Info</td>
            <td colspan='3' id='grey_center' >  Buffer Size</td>
            <td colspan='3' style='text-align: right;'>$redo_buffer_size </td>
            <td colspan='3' id='grey_center'>  trx_commit</td>
            <td colspan='3' >$trx_commit</td>
            <td rowspan='2'>OK</td>
        </tr>
        <tr>
            <td colspan='3' id='grey_center'>  File Size </td>
            <td colspan='3' style='text-align: right;'>$innodb_log_file_size </td>
            <td colspan='3' id='grey_center'> Group</td>
            <td colspan='3'>$innodb_log_files_in_group</td>
        </tr>
    </Redo_log_Info>

    <Binary_log>
        <tr>
            <td rowspan='2' id='left' > ■ Binary log</td>
            <td colspan='3' id='grey_center'> Cache Size</td>
            <td colspan='3' style='text-align: right;'>$binlog_cache_size </td>
            <td colspan='3' id='grey_center'> Expire Log Day</td>
            <td colspan='3'>$expire_logs_days</td>
            <td rowspan='2'>OK</td>
        </tr>
        <tr>
            <td colspan='3' id='grey_center'> Current File</td>
            <td colspan='3'style='text-align: center;' >$master_status_file</td>
            <td colspan='3'id='grey_center'> Position</td>
            <td colspan='3' >$master_status_position</td>
        </tr>
    </Binary_log>

    <Backup>
        <tr>
            <td  id='left' > ■ Backup</td>
            <td colspan='3' id='grey_center' > Status</td>
            <td colspan='3'></td>
            <td colspan='3' id='grey_center' > Usage</td>
            <td colspan='3'></td>
            <td>OK</td>
        </tr>
    </Backup>

    <Connection>
        <tr>
            <td rowspan='4' id='left' > ■ Connection</td>
            <td colspan='3' id='grey_center' style='border-bottom: 2px black solid;'> Socket</td>
            <td colspan='3' style='border-bottom: 2px black solid;'>$socket_info</td>
            <td colspan='3' id='grey_center' style='border-bottom: 2px black solid;'> Port</td>
            <td colspan='3' style='border-bottom: 2px black solid;'>$port_info</td>
            <td rowspan='4'>OK</td>
        </tr>
        <tr>
            <td colspan='6' id='blockin' > ▪ Max Connection : $max_connections</td>
            <td colspan='6' id='blockin'> ▪ Threads Connection : $Threads_connected</td>
        </tr>
        <tr>
            <td colspan='6' id='blockin'> ▪ Max Used Connection : $Max_used_connections</td>
            <td colspan='6' id='blockin'> ▪ Threads Created : $Threads_created</td>
        </tr>
        <tr>
            <td colspan='6' id='blockin' > ▪ Connection : $Connections</td>
            <td colspan='6' id='blockin'> ▪ Threads Running : $Threads_running</td>
        </tr>
    </Connection>
    
    <Process_Status>
        <tr>
            <td rowspan='3' id='left' >  ■ Process Status</td>
            <td colspan='2' id='grey_center' >  Id</td>
            <td colspan='2' id='grey_center' >  User</td>
            <td colspan='2' id='grey_center' > Host</td>
            <td colspan='2' id='grey_center' > DB</td>
            <td colspan='2' id='grey_center' > CMD</td>
            <td colspan='2' id='grey_center' > Time</td>
            <td rowspan='3' >OK</td>
        </tr>
        <tr>
            <td colspan='2' style='width: 11%;' >$PS_id1</td>
            <td colspan='2' style='width: 11%;' >$PS_user1</td>
            <td colspan='2' style='width: 11%;' >$PS_host1</td>
            <td colspan='2' style='width: 11%;' >$PS_db1</td>
            <td colspan='2' style='width: 11%;' >$PS_cmd1</td>
            <td colspan='2' style='width: 11%;' >$PS_time1</td>
        </tr>
        <tr>
            <td colspan='2'>$PS_id2</td>
            <td colspan='2'>$PS_user2</td>
            <td colspan='2'>$PS_host2</td>
            <td colspan='2'>$PS_db2</td>
            <td colspan='2'>$PS_cmd2</td>
            <td colspan='2'>$PS_time2</td>
        </tr>
    </Process_Status>
    
    <Warnings>
        <tr>
            <td rowspan='1' id='left'> ■ Warnings</td>
            <td colspan='12' style='text-align: left;'>$Warnings_Msg</td>
            <td rowspan='1'>OK</td>
        </tr>
    </Warnings>
    
    <Error_log>
        <td rowspan='1' id='left' > ■ Error log</td>
        <td colspan='12' style='text-align: left;'>$Error_Msg</td>
        <td rowspan='1'>OK</td>
    
    </Error_log>

</table>
</medium>

<button_layer>
<small_title id='small_title' style='font-weight: bold;' >
    ▣ COMMENT
</small_title>
<table>
    <p style='border: 2px black solid ; margin: 0 auto; height:21px; height: 1.5cm;'></p>
</table>
<small_title id='small_title' style='font-weight: bold; border-bottom: none;'>
    ▣ SUPPORT TIME
</small_title>
<table>
    <tr>
    <td id='grey' style='width: 15%; text-align: center;'>Start Time</td>
    <td style='width: 15%; text-align: center; color: grey;'>시작시간</td>
    <td id='grey' style='width: 15%; text-align: center;'>End Time</td>
    <td style='width: 15%; text-align: center; color: grey;'>종료시간</td>
    <td id='grey' style='width: 15%; text-align: center;'>ASC</td>
    <td style='width: 15%; text-align: center; color: grey;'>ASC 시간</td>
    </tr>
</table>
</button_layer>

<footer_leader>
<table id='last' style='margin-top:3px; border: 0px;'>
    <tr>
        <td id='last1'  style='font-weight: bold; font-size: small; '> Repaired by</td>
        <td id='last2'  style='border-bottom: none;'></td>
        <td id='last1' style='font-weight: bold;  font-size: small;'>Accepted by</td>
    </tr>
    <tr>
        <td id='last1' >O Date</td>
        <td id='last2'  style='width:30%;text-align: center;'> `date '+%Y-%m-%d'` </td>
        <td id='last1'>O Dept</td>
        <td id='last2'>OK</td>
    </tr>
    <tr>
        <td id='last1'  >O DBA</td>
        <td id='last2' style='text-align: center;' > $confirm</td>
        <td id='last1'>O Customer</td>
        <td id='last2' style='width:30%; text-align: center;'>$manager</td>
    </tr>
</table>
</footer_leader>
</body>

</html>

" > $html_path





#
#######################################
#
#  Make Output File
#
#######################################
#

            rm -rf $outfile_path
            echo "

            ===================
            O/S Information  
            ===================

            ▪ Host : $host_name

            ▪ Server : 
                
                O/S     : $os_ver
                CPU     : $cpu 
                Mem     : $os_memory
                
                Start   : $os_uptime
                
                IP Addr : $if_config

            ▪ Disk (datadir) :
                
                Mount point : $Mounted 
                    Total : $dfSize
                    Used  : $dfUse_size ($dfUse)
                    Free  : $dfAvail


            =====================
            MySQL Information  
            =====================

            ▪ MySQL : 
                
                $full_db_name ($db_version) - $server_state
                
                Start : $DB_Start_Up
                
                Conf File : $my_cnf

                Base dir : $basedircheck
                Data dir : $datadir

                Socket : $socket_info
                Port   : $port_info
                
            ▪ Prameters :

                Default engine : $db_engine
                Character set  : $character

                Max connections : $max_connections

                Isolation : $isolation

                InnoDB Buffer size : $innodb_bf_size

                Performance schema : $performance_schema
                
                Slow query : $slow_query_exict
                Slow query(s) : $slow_second

                Redo log buffer        : $redo_buffer_size
                Redo Flush (trx_commit): $trx_commit 

                Redo File Size         : $innodb_log_file_size
                Redo groups            : $innodb_log_files_in_group
                

                Binlog cache size : $binlog_cache_size
                Binlog expire days: $expire_logs_days

            ▪ Current Log : $master_status_file ($master_status_position)
                
            ▪ Query : 
                
                Average Query time(s) : $avg_query_time
                Slow query count : $slow_query_count

            ▪ Object Info :
                
                Total data size : $data_size 
                Total index size : $index_size
                
                User Objects :

                    Size (Data/Index MB):
            " > $outfile_path

            last_path=0;
            for (( show_val=0; show_val< ${#engine_profile[@]} ; show_val+=2))
            do  

            #echo "$show_val"
            echo " SHEMA : ${engine_profile[ $show_val ]} " >> $outfile_path
            next_level=$((show_val+1))
            #echo "$next_level"
            #echo "  ${engine_profile[ $next_level ]} "
            for (( val=0; val< ${engine_profile[ $next_level ]} ; val++))
            do  
                TYPE_val=$(echo $all_list | awk -v field="$((4+2+$last_path*4+$val*4))"  '{print $field }')
                COUNT_val=$(echo $all_list | awk -v field="$((4+3+$last_path*4+$val*4))"  '{print $field }')
                SIZE_val=$(echo $all_list | awk -v field="$((4+4+$last_path*4+$val*4))"  '{print $field }')
                echo "
                TYPE : $TYPE_val
                COUNT : $COUNT_val " >> $outfile_path
                if [[ "$TYPE_val" == *TABLE* ]]; then
            CUT_SIZE_val=$( cut_parameter $SIZE_val )
                echo "                SIZE : $CUT_SIZE_val 
                " >> $outfile_path
                fi
            done
            last_path=$(($last_path+$val))
            echo " "  >> $outfile_path
            done   


            echo "
            $user_data_size_out

                    Counts :

                        Database  : $database_cnt
                        
                        Table     : $table_cnt
                        Index     : $index_cnt
                        View      : $view_cnt
                        
                        Procedure : $procedure_cnt
                        Function  : $function_cnt
                        Trigger   : $trigger_cnt
                        
                        Unused Idx: $unused_index_cnt

            ▪ Connections :
                
                Max used : $Max_used_connections
                Thread created : $Threads_created
                Connections      : $Connections

                Thread connected : $Threads_connected
                Thread running   : $Threads_running

            ▪ Replication :
                Replication : $server_state
                read ONly : $read_only_statu

            ▪ Slave Infomation :
                
                Master server   : $master_host
                Master log(pos) : $Slave_Log_File_Pos
                
                Running SQL/IO  : $Slave_IO_Running

                Seconds behind  : $Seconds_Behind_Master

            ▪ Top Process list (elapsed time > 10 , time desc 10)

                Data : user , db , elapsed time(s) , query  

            $top_session_10

            ▪ Error :
                
                $Error_Msg

            ▪ Warning :
                
                $Warnings_Msg

            " >> $outfile_path

clear
        ############################################
#
#  Delete shell conf file
#

rm $conf_path


cat $outfile_path
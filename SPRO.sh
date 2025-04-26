#!/bin/bash

MY_NAME="SPRO"        # Название данного объекта
Max_N_Targets=5       # Максимальное количество целей (согласовано с генератором)


# Папка, где находятся файлы
TMP_DIR="/tmp/GenTargets"

TARGET_DIR="$TMP_DIR/Targets"
DESTROY_DIR="$TMP_DIR/Destroy"

FOUNDED_OBJ="sproFoundedObj.txt"
FOUNDED_FIRST_TARG="sproFirstTarget.txt"
REPORTED_TARG="sproReported.txt"

SHOOTING_TARGETS_ID="sproShootingTarget.txt"

# Директория для сообщений
MSG_DIR="./messages"
rm $MSG_DIR/*

# Файл обработанных "файлов c именами"
> $FOUNDED_OBJ

# Файл первичных засечек (ID + coord)
> $FOUNDED_FIRST_TARG

# Файл с ID целей, по которым стреляли
> $SHOOTING_TARGETS_ID

# Файл c обработанными (переданными) целями 
# РЛС проверяет цель на отсутствие записи о ней здесь, иначе будет повторная выдача
> $REPORTED_TARG

# Параметры СПРО [м, град.]
SPRO_X=$((3300*1000))
SPRO_Y=$((3500*1000))
SPRO_RADIUS=$((1100*1000))
SPRO_AMMUNITION=2   # Боезапас
RECHARGE_PERIOD=20  # Период перезарядки (в тактах)

# Функция конвертации строки hex в массив char
convert_hex_2_char() {
	# Название файла как строки
	filename="$1"
	
	# Удаляем 2 символа с конца (мусор)
	cut_filename="${filename:0:-2}"
	hex_str=""
	
	# Перешагиваем через каждые 2 символа и берем 2 символа
	for((i=0; i<${#cut_filename}; i+=4)) 
	do
		hex_str+="${cut_filename:$i+2:2}"
	done
	
	# Конвертация hex в str
	id_target=$(echo $hex_str | xxd -r -p)
	
	# Отправляем в стандартный вывод
	echo $id_target
}

# Функция вычисления скорости [м/c] по 2 точкам 
calculate_speed() {
    local x0=$1
    local y0=$2
    local x1=$3
    local y1=$4

	local speed

	# Время = 1 сек, так как считаем за 1 такт
	local time=1

	# Вычисление расстояния между двумя точками
	# bc - это калькулятор
	local distance=$(echo "sqrt(($x1 - $x0)^2 + ($y1 - $y0)^2)" | bc)

	# Вычисление скорости [м]
	speed=$(echo "$distance / $time" | bc)

    echo $speed
}

# Функция определения типа цели по скорости
get_type_target() {
	local speed=$1
	local type_target=''

	if [ $speed -gt 49 ] && [ $speed -lt 250 ]; then
		type_target='Самолёт'
	elif [ $speed -gt 250 ] && [ $speed -lt 1000 ]; then
		type_target='Крылатая ракета'
	elif [ $speed -gt 8000 ] && [ $speed -lt 10000 ]; then
		type_target='ББ БР'
	fi

	echo $type_target
}

# Функция проверки вхождения в зону обзора
can_i_see() {
	local x=$1
    local y=$2

	# Условие 1: дальность до цели меньше радиуса обнаружения
	# TODO: Условие 2: входит в сектор обзора

	distance=$(echo "sqrt(($x - $SPRO_X)^2 + ($y - $SPRO_Y)^2)" | bc)

	if [ $distance -lt $SPRO_RADIUS ]; then
		# 0 - результат выполнения без ошибки (true)
		return 0
	else
		return 1    
	fi
}

# Функция создания файла с ЗАШИФРОВАННЫМ сообщением на КП
send_msg() {
	local msg=$1

	# Шифрование строки
	msg=$(echo "| $MY_NAME | $msg" | rev) 

	# Текущее время в нано сек
	local time=$(date +%s%N)
	echo "$msg" > "$MSG_DIR/${MY_NAME}_${time}.txt"
}

i=0
# Заряжаем систему
ammunition=$SPRO_AMMUNITION		# оставшееся количество боезапаса [шт]
i_out_ammunition=0  			# Такт, на котором закончился боезапас

while :
do
	# Счетчик такта
	echo "--------------------"
	echo $i
	((i++))

	# Массив объектов за текущий такт (если меняю количество max целей в генераторе, то head тоже изменить)
	list_targets=$(ls -t $TARGET_DIR | head -n $Max_N_Targets)

	# Перезаряжаемся, если прошёл КД или нет хотя бы одного заряда
	if (($i - $i_out_ammunition > $RECHARGE_PERIOD)) && (( $ammunition != $SPRO_AMMUNITION )); then
		ammunition=$SPRO_AMMUNITION
		
		# Сообщаем о том, что перезарядились
		msg="Боезапас $MY_NAME пополнен"
		echo $msg
		send_msg "$msg"
	fi
	
	# Читаем координаты объекта
	for targ in $list_targets
	do
		# Проверяем на наличие во временном файле (чтобы на одной итерации обработать цель ТОЛЬКО 1 раз) 
		if grep -q $targ $FOUNDED_OBJ; then
			# Уже записали -> пропускаем
			continue
		else
			# Впервые видим -> записываем и обрабатываем дальше
			echo $targ >> $FOUNDED_OBJ
		fi

		# Декодируем ID через функцию конвертации convert_hex_2_char
		id_target=$(convert_hex_2_char "$targ")
			
		# Проверяем, был ли объект засечён раньше
		if grep -q $id_target $FOUNDED_FIRST_TARG; then
			# Если уже записали ранее, имеем дело с 2-й засечкой	
			
			# Если цель обнаружена в файле с выстрелами, значит промахнулись
			if grep -q $id_target $SHOOTING_TARGETS_ID; then
				# Сообщаем о промахе
				msg="Промах ID: $id_target" 
				echo $msg
				send_msg "$msg"

				# Удаляем из файла о выстрелах этот ID
                sed -i "/$id_target/d" $SHOOTING_TARGETS_ID

				# Если боекмоплекта нет -> стрелять не можем, пропускам итерацию
				if [ $ammunition -eq 0 ]; then
					continue            
				fi

                # Повторный выстрел (если есть заряд)
                echo $MY_NAME >> $DESTROY_DIR/$id_target
				((ammunition--))

                # Новая запись и сообщение о выстреле
                echo $id_target $i >> $SHOOTING_TARGETS_ID

                # Сообщаем о выстреле
                msg="Выстрел в цель ID: $id_target"
				echo $msg
				send_msg "$msg"

				# Если закончился боекомплект -> сообщаем
				if [ $ammunition -eq 0 ]; then
					msg="Закончился боекомплект"
					echo $msg
					send_msg "$msg"      

					# Запоминаем такт, на котором закончился боекомплект
					i_out_ammunition=$i      
				fi

				# Итерация закончена
                continue
			fi		
            
    		# Проверяем, НЕ сообщили ли на КП об объекте раньше (либо раньше уже "отмели" как "неподоходящий тип")
			if grep -q $id_target $REPORTED_TARG; then
				# Если уже сообщали, то пропускаем эту цель
				continue
			fi
            
			# Получаем НОВЫЕ координаты в формате "X: ... Y: ..."
			coord=$(cat $TARGET_DIR/$targ)
			
			# Новая координата Х и Y
			x_coord=$(echo $coord | awk '{print $2}')
			y_coord=$(echo $coord | awk '{print $4}')
			
			# Получаем старые координаты (с предыдущего такта, когда был обнаружен впервые)
			x0_coord=$(grep $id_target $FOUNDED_FIRST_TARG | cut -d " " -f2)
			y0_coord=$(grep $id_target $FOUNDED_FIRST_TARG | cut -d " " -f3)

			# Вычисление скорости через координаты
			speed=$(calculate_speed $x0_coord $y0_coord $x_coord $y_coord)
			
			# Если скорость нулевая, игнорируем цель, помечаем как "рассмотренная"
			if [ $speed -eq 0 ]; then
				echo $id_target >> $REPORTED_TARG
				continue
			fi

			# Определение типа цели по скорости
			type_target=$(get_type_target $speed)

			# Если тип цели не наш, игнорируем, помечаем как "рассмотренная"
			if [ "$type_target" != 'ББ БР' ]; then
				echo $id_target >> $REPORTED_TARG
				continue
			fi

			# Если не входит в зону видимости, игнорируем цель
			# if ! can_i_see $x_coord $y_coord; then
			# 	continue
			# fi

			# Запоминаем время обнаружения 
			# time=$(date '+%H:%M:%S:%N' | cut -d. -f1)

			# Отправляем сообщение
			msg="Обнаруж. $type_target Speed: $speed ID: $id_target с коорд: $coord"
			echo $msg
			send_msg "$msg"
			
			# Указываем в REPORTED_TARG, что информация о цели обработана
			echo $id_target >> $REPORTED_TARG

			# Если боекмоплекта нет -> стрелять не можем, пропускам итерацию
			if [ $ammunition -eq 0 ]; then
				continue            
			fi

			# Выстрел (если есть заряд)
			echo $MY_NAME >> $DESTROY_DIR/$id_target
			((ammunition--))

			# Записываем ID цели в БД о том, что по цели был выстрел + номер такта
			echo $id_target $i >> $SHOOTING_TARGETS_ID

            # Сообщаем о выстреле
            msg="Выстрел в цель ID: $id_target"
			echo $msg
			send_msg "$msg"

			# Если закончился боекомплект -> сообщаем
			if [ $ammunition -eq 0 ]; then
				msg="Закончился боекомплект"
				echo $msg
				send_msg "$msg"            
			fi

		else
			# Заметили впервые -> записываем
			
			# Координаты в формате "X: ... Y: ..."
			coord=$(cat $TARGET_DIR/$targ)
			
			# Координата Х и Y
			x_coord=$(echo $coord | awk '{print $2}')
			y_coord=$(echo $coord | awk '{print $4}')				

			# Записываем в файл как 1-я засечка (ID X Y)
			echo $id_target $x_coord $y_coord >> $FOUNDED_FIRST_TARG			
		fi
	done

    # Проверяем БД обстреленных целей на наличие сбитых
    while IFS= read -r line; do
        # Если разница в тактах больше 1, значит цель больше не появлялась -> сбита
        i_shoot=$(echo "$line" | awk '{print $2}')
        if (( i_shoot < i-1 )); then
            id_trg=$(echo "$line" | awk '{print $1}')

            # Удаляем из файла о выстрелах этот ID
            sed -i "/$id_trg/d" $SHOOTING_TARGETS_ID

            # Сообщаем, что цель сбита
            msg="Сбита цель ID: $id_trg"
			echo $msg
			send_msg "$msg" 
        fi
    done < "$SHOOTING_TARGETS_ID"
    
	sleep 0.5
done

# Как исправить баг с ложным попаданием:
# В журнале выстрелов возле каждой цели ставить - в начале каждой главной итерации while
# Если эта цель попалась в итерации for, то возле неё ставим "+"
# В конце проверяем список, те у кого стоит - считаем сбитыми
# при выстреле (создании новой записи о выстреле) не забыть поставить возде цели "+"
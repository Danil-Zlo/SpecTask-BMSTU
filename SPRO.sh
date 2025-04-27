#!/bin/bash

source ./pkg/functions.sh

MY_NAME="SPRO"        # Название данного объекта

# Параметры СПРО [м, град.]
SPRO_X=$((3300*1000))
SPRO_Y=$((3500*1000))
SPRO_RADIUS=$((11000*1000))
SPRO_AMMUNITION=20   # Боезапас [шт.]
RECHARGE_PERIOD=20  # Период перезарядки [такт]

TMP_DIR="/tmp/GenTargets"

TARGET_DIR="$TMP_DIR/Targets"
DESTROY_DIR="$TMP_DIR/Destroy"

DB_DIR="./db"
FOUNDED_OBJ="$DB_DIR/sproFoundedObj.txt"
FOUNDED_FIRST_TARG="$DB_DIR/sproFirstTarget.txt"
REPORTED_TARG="$DB_DIR/sproReported.txt"
SHOOTING_TARGETS_ID="$DB_DIR/sproShootingTarget.txt"

# Директория для сообщений
MSG_DIR="./messages"

# Файл обработанных "файлов c именами"
> $FOUNDED_OBJ

# Файл первичных засечек (ID + coord)
> $FOUNDED_FIRST_TARG

# Файл с ID целей, по которым стреляли
> $SHOOTING_TARGETS_ID

# Файл c обработанными (переданными) целями 
# РЛС проверяет цель на отсутствие записи о ней здесь, иначе будет повторная выдача
> $REPORTED_TARG

i=0
# Заряжаем систему
ammunition=$SPRO_AMMUNITION		# оставшееся количество боезапаса [шт]
i_out_ammunition=0  			# Такт, на котором закончился боезапас

while :
do
	# Счетчик такта
	# echo "--------------------"
	# echo $i
	((i++))

	# Массив объектов за текущий такт (если меняю количество max целей в генераторе, то head тоже изменить)
	list_targets=$(ls -t $TARGET_DIR | head -n $Max_N_Targets)

	# Перезаряжаемся, если прошёл КД и боекомплект пустой
	if (($i - $i_out_ammunition > $RECHARGE_PERIOD)) && (( $ammunition == 0 )); then
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
			if ! can_i_see $x_coord $y_coord $SPRO_X $SPRO_Y $SPRO_RADIUS; then
				continue
			fi

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

				# Запоминаем такт, на котором закончился боекомплект
				i_out_ammunition=$i         
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
	sleep $TACT
done

# Как исправить баг с ложным попаданием:
# В журнале выстрелов возле каждой цели ставить - в начале каждой главной итерации while
# Если эта цель попалась в итерации for, то возле неё ставим "+", считаем, что промахнулись и стреляем повторно
# В конце проверяем список, те у кого стоит - считаем сбитыми
# при выстреле (создании новой записи о выстреле) не забыть поставить возде цели "+"
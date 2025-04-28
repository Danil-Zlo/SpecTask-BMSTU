#!/bin/bash

source ./pkg/functions.sh

MY_NAME="ZRDN2"        # Название данного объекта

# Параметры ЗРДН2 Уфа [м, град.]
ZRDN_X=$((4400*1000))
ZRDN_Y=$((3750*1000))
ZRDN_RADIUS=$((400*1000))
ZRDN_AMMUNITION=20   # Боезапас [шт.]
RECHARGE_PERIOD=20  # Период перезарядки [такт]

TMP_DIR="/tmp/GenTargets"

TARGET_DIR="$TMP_DIR/Targets"
DESTROY_DIR="$TMP_DIR/Destroy"

DB_DIR="./db"
FOUNDED_OBJ="$DB_DIR/${MY_NAME}-FoundedObj.txt"
FOUNDED_FIRST_TARG="$DB_DIR/${MY_NAME}-FirstTarget.txt"
REPORTED_TARG="$DB_DIR/${MY_NAME}-Reported.txt"
SHOOTING_TARGETS_ID="$DB_DIR/${MY_NAME}-ShootingTarget.txt"
HOLDING_TARGETS_ID="$DB_DIR/${MY_NAME}-HoldingTarget.txt"

# Директория для сообщений
MSG_DIR="./messages"

# Файл обработанных "файлов c именами"
> $FOUNDED_OBJ

# Файл первичных засечек (ID + coord)
> $FOUNDED_FIRST_TARG

# Файл с ID целей, по которым стреляли
> $SHOOTING_TARGETS_ID

# Файл с ID сопровождаемых целей
> $HOLDING_TARGETS_ID

# Файл c обработанными (переданными) целями 
# Объект проверяет цель на отсутствие записи о ней здесь, иначе будет повторная выдача
> $REPORTED_TARG

i=0
# Заряжаем систему
ammunition=$ZRDN_AMMUNITION		# оставшееся количество боезапаса [шт]
i_out_ammunition=0  			# Такт, на котором закончился боезапас

while :
do
	# Счетчик такта
	# echo "--------------------"
	# echo $i
	((i++))

	# Массив объектов за текущий такт (если меняю количество max целей в генераторе, то head тоже изменить)
	list_targets=$(ls -t $TARGET_DIR | head -n $Max_N_Targets)

	# Всем обстреленным целям ставим "-" (в дальнейшем отмечаем "+", если встретится на итерации)
	if [[ $((i % 2)) -eq 0 ]] && grep -q '+' "$SHOOTING_TARGETS_ID"; then	
		sed -i -e 's/+/-/g' $SHOOTING_TARGETS_ID
	fi

	# Перезаряжаемся, если прошёл КД и боекомплект пустой
	if (($i - $i_out_ammunition > $RECHARGE_PERIOD)) && (( $ammunition == 0 )); then
		ammunition=$ZRDN_AMMUNITION
		
		# Сообщаем о том, что перезарядились
		msg="[ Боекомплект $MY_NAME пополнен ]"
		echo $msg
		send_msg "$msg"

		# Обстрел отслеживаемых целей (когда пополнили боекомплект)
		while IFS= read -r line; do	
			if [ $ammunition -gt 0 ]; then				
				id_trg=$(echo "$line" | awk '{print $1}')
				
				# Удаляем цель из списка сопровождаемых
                sed -i "/$id_trg/d" $HOLDING_TARGETS_ID
	
                # Выстрел
                echo $MY_NAME >> $DESTROY_DIR/$id_trg
				((ammunition--))

				# Отмечаем в списке выстрелов эту цель
				echo "$id_trg +" >> $SHOOTING_TARGETS_ID
				
                # Сообщаем о выстреле
                msg="Выстрел в цель ID: $id_trg"
				echo $msg
				send_msg "$msg"

				# Если закончился боекомплект -> сообщаем
				if [ $ammunition -eq 0 ]; then
					msg="[ Закончился боекомплект $MY_NAME ]"
					echo $msg
					send_msg "$msg"      

					# Запоминаем такт, на котором закончился боекомплект
					i_out_ammunition=$i

					# Выход из цикла
					break
				fi

			fi
		done < "$HOLDING_TARGETS_ID"
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
			
			# Если цель в списке сопровождаемых -> игнорируем 
			if grep -q $id_target $HOLDING_TARGETS_ID; then
				continue
			fi

			# Если цель обнаружена в файле с выстрелами, значит промахнулись
			if grep -q $id_target $SHOOTING_TARGETS_ID; then
				msg="ПРОМАХ      $id_target" 
				echo $msg
				send_msg "$msg"

				# Удаляем из файла о выстрелах этот ID
                sed -i "/$id_target/d" $SHOOTING_TARGETS_ID

				# Если боекмоплекта нет -> стрелять не можем, пропускам итерацию
				if [ $ammunition -eq 0 ]; then
					msg="Сопровождаю $id_target. Ожидаю боеприпасов." 
					echo $msg
					send_msg "$msg"

					# Цель в список сопровождаемых
					echo "$id_target" >> $HOLDING_TARGETS_ID
					continue            
				fi
				
                # Повторный выстрел (если есть заряд)
                echo $MY_NAME >> $DESTROY_DIR/$id_target
				((ammunition--))

				# Отмечаем в списке выстрелов эту цель
				echo "$id_target +" >> $SHOOTING_TARGETS_ID
				
                # Сообщаем о выстреле
                msg="Выстрел в цель ID: $id_target"
				echo $msg
				send_msg "$msg"

				# Если закончился боекомплект -> сообщаем
				if [ $ammunition -eq 0 ]; then
					msg="[ Закончился боекомплект $MY_NAME ]"
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
			if [ "$type_target" == 'ББ БР' ]; then
				echo $id_target >> $REPORTED_TARG
				continue
			fi

			# Если не входит в зону видимости, игнорируем цель
			if ! can_i_see $x_coord $y_coord $ZRDN_X $ZRDN_Y $ZRDN_RADIUS; then
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
				msg="Сопровождаю $id_target. Ожидаю боеприпасов." 
				echo $msg
				send_msg "$msg"

				# Цель в список сопровождаемых
				echo "$id_target" >> $HOLDING_TARGETS_ID
				continue            
			fi

			# Выстрел (если есть заряд)
			echo $MY_NAME >> $DESTROY_DIR/$id_target
			((ammunition--))

			# Записываем ID цели в БД о том, что по цели был выстрел
			echo "$id_target +" >> $SHOOTING_TARGETS_ID

            # Сообщаем о выстреле
            msg="Выстрел в цель ID: $id_target"
			echo $msg
			send_msg "$msg"

			# Если закончился боекомплект -> сообщаем
			if [ $ammunition -eq 0 ]; then
				msg="[ Закончился боекомплект $MY_NAME ]"
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

    # Проверяем БД обстреленных целей на наличие сбитых (каждые 2 такта)
	if [[ $((i % 2)) -eq 1 ]]; then	
		while IFS= read -r line; do		
			# Если строка содержит "-" -> её не было на этой итерации -> сбили
			
			flag=$(echo "$line" | awk '{print $2}')
			if [[ "$flag" == "-" ]]; then
				id_trg=$(echo "$line" | awk '{print $1}')
				# Удаляем из файла о выстрелах этот ID
				sed -i "/$id_trg/d" $SHOOTING_TARGETS_ID

				# Сообщаем, что цель сбита
				msg="Сбита цель ID: $id_trg"
				echo $msg
				send_msg "$msg" 
			fi
		done < "$SHOOTING_TARGETS_ID"
	fi

	sleep $TACT
done
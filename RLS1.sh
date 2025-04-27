#!/bin/bash

source ./pkg/functions.sh

MY_NAME="RLS1"        # Название данного объекта

# Параметры РЛС1 [м, град.]
# Хабаровск. Воронеж-ДМ
RLS_X=$((9500*1000))
RLS_Y=$((3000*1000)) 
RLS_RADIUS=$((4000*1000))
RLS_SECTOR=200 
RLS_ROTATE_ANGLE=315

# Параметры СПРО
SPRO_X=$((3300*1000))
SPRO_Y=$((3500*1000))
SPRO_RADIUS=$((1100*1000))

# Папка, где находятся файлы
TMP_DIR="/tmp/GenTargets"

TARGET_DIR="$TMP_DIR/Targets"
DESTROY_DIR="$TMP_DIR/Destroy"

DB_DIR="./db"
FOUNDED_OBJ="$DB_DIR/rls1FoundedObj.txt"
FOUNDED_FIRST_TARG="$DB_DIR/rls1FirstTarget.txt"
REPORTED_TARG="$DB_DIR/rls1Reported.txt"

# Директория для сообщений
MSG_DIR="./messages"

# Файл обработанных "файлов c именами"
> $FOUNDED_OBJ

# Файл первичных засечек (ID + coord)
> $FOUNDED_FIRST_TARG

# Файл c обработанными (переданными) целями 
# РЛС проверяет цель на остуствие записи о ней здесь, иначе будет повторная выдача
> $REPORTED_TARG

i=0

while :
do
	# Счетчик такта
	# echo "--------------------"
	# echo $i
	((i++))

	# Массив объектов за текущий такт 
	list_targets=$(ls -t $TARGET_DIR | head -n 50)
	
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

			# Проверяем, НЕ сообщили ли на КП об объекте раньше
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
			
			# Если скорость нулевая, игнорируем цель
			if [ $speed -eq 0 ]; then
				echo $id_target >> $REPORTED_TARG
				continue
			fi

			# Определение типа цели по скорости
			type_target=$(get_type_target $speed)

			# Если тип цели не наш, игнорируем
			if [ "$type_target" != 'ББ БР' ]; then
				echo $id_target >> $REPORTED_TARG
				continue
			fi

			# Если не входит в зону видимости, игнорируем цель
			if ! can_i_see $x_coord $y_coord $RLS_X $RLS_Y $RLS_RADIUS; then
				continue
			fi
			# Запоминаем время обнаружения 
			# time=$(date '+%H:%M:%S:%N' | cut -d. -f1)

			# Отправляем сообщение
			msg="Обнаруж. $type_target Speed: $speed ID: $id_target с коорд: $coord"
			echo $msg
			send_msg "$msg"

			# Определяем, попадёт ли цель в зону СПРО
			if can_SPRO_see $x0_coord $y0_coord $x_coord $y_coord; then
				msg="Цель ID: $id_target движется в направлении СПРО (Воронеж)"
				echo $msg
				send_msg "$msg"
			fi			
			
			# Указываем в REPORTED_TARG, что информация о цели обработана
			echo $id_target >> $REPORTED_TARG
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
	sleep $TACT
done
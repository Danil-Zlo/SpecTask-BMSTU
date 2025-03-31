#!/bin/bash

# Папка, где находятся файлы
TMP_DIR="/tmp/GenTargets"

TARGET_DIR="$TMP_DIR/Targets"
DESTROY_DIR="$TMP_DIR/Destroy"

FOUNDED_OBJ="rls1FoundedObj.txt"
FOUNDED_FIRST_TARG="rls1FirstTarget.txt"
REPORTED_TARG="rls1Reported.txt"

# Файл обработанных "файлов c именами"
> $FOUNDED_OBJ

# Файл первичных засечек (ID + coord)
> $FOUNDED_FIRST_TARG

# Файл c обработанными (переданными) целями 
# РЛС проверяет цель на остуствие записи о ней здесь, иначе будет повторная выдача
> $REPORTED_TARG

# Параметры РЛС [м, град.]
# Воронеж
RLS_X=$((9500*1000))
RLS_Y=$((3000*1000)) 
RLS_RADIUS=$((4000*1000))
RLS_SECTOR=200 
RLS_ROTATE_ANGLE=315


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

    local time=1

    # Вычисление расстояния между двумя точками
	# bc - это калькулятор
    local distance=$(echo "sqrt(($x1 - $x0)^2 + ($y1 - $y0)^2)" | bc)

    # Вычисление скорости [м]
    local speed=$(echo "$distance / $time" | bc)

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

	distance=$(echo "sqrt(($x - $RLS_X)^2 + ($y - $RLS_Y)^2)" | bc)
	if [ $distance -lt $RLS_RADIUS ]; then
		return 1
	else
		return 0
	fi
}

i=0

while :
do
	# Счетчик такта
	echo "--------------------"
	echo $i
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
			
			# Если не входит в зону видимости, игнорируем цель
			# if ! can_i_see $x_coord $y_coord; then
			# 	continue
			# fi

			# Вычисление скорости через координаты
			speed=$(calculate_speed $x0_coord $y0_coord $x_coord $y_coord)

			# Если скорость нулевая, игнорируем цель
			if [ $speed -eq 0 ]; then
				continue
			fi

			# Определение типа цели по скорости
			type_target=$(get_type_target $speed)

			# Если тип цели не наш, игнорируем
			if [ "$type_target" != 'ББ БР' ]; then
				continue
			fi

			# Запоминаем время обнаружения 
			time=$(date '+%H:%M:%S:%N' | cut -d. -f1)

			# Отправляем сообщение
			msg="В $time обнаруж. $type_target ID: $id_target с коорд: $coord"
			echo $msg
			# TODO: добавить инфу, если летит в направлении СПРО
			
			# Указываем в REPORTED_TARG, что информация о цели обработана
			echo $id_target >> $REPORTED_TARG
		else
			# Заметили впервые -> записываем
			echo $targ >> $FOUNDED_OBJ
			
			# Координаты в формате "X: ... Y: ..."
			coord=$(cat $TARGET_DIR/$targ)
			
			# Координата Х и Y
			x_coord=$(echo $coord | awk '{print $2}')
			y_coord=$(echo $coord | awk '{print $4}')				

			# Записываем в файл как 1-я засечка (ID X Y)
			echo $id_target $x_coord $y_coord >> $FOUNDED_FIRST_TARG			
		fi
	done
	sleep 0.5
done

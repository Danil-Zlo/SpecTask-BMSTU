#!/bin/bash

TACT=0.5  # Такт [c]
Max_N_Targets=1       # Максимальное количество целей (согласовано с генератором)

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

	local ob_x=$3
	local ob_y=$4

	local R=$5

	# Условие 1: дальность до цели меньше радиуса обнаружения
	# TODO: Условие 2: входит в сектор обзора

	distance=$(echo "sqrt(($x - $ob_x)^2 + ($y - $ob_y)^2)" | bc)

	if [ $distance -lt $R ]; then
		# 0 - результат выполнения без ошибки (true)
		return 0
	else
		return 1    
	fi
}

# Функция определения направления движения цели
# Возвращает 1, если цель летит в направлении СПРО. Иначе - 0
can_SPRO_see() {
	# Координаты СПРН 
	local x=$SPRO_X
	local y=$SPRO_Y
	local R=$SPRO_RADIUS

	# Координаты цели
	local x1=$1
	local y1=$2
	local x2=$3
	local y2=$4

	A=$(echo "($x2 - $x1)^2 + ($y2 - $y1)^2" | bc)
	B=$(echo "2 * (($x2 - $x1) * ($x1 - $x) + ($y2 - $y1) * ($y1 - $y))" | bc)
	C=$(echo "($x1 - $x)^2 + ($y1 - $y)^2 - $R^2" | bc)

	# ABC - множители квадратного уравнения
	# D - дискриминант
	
	D=$(echo "$B^2 - 4 * $A * $C" | bc)

    # Если D < 0, пересечения нет;
    # если D = 0, есть одно пересечение, прямая и окружность касаются;
    # если D > 0, прямая и окружность пересекаются в двух точках.
	
	# Флаг -l для работы с большими числами 
	if (( $(echo "$D >= 0" | bc -l) )); then
		# 0 - true
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

# Функция ДЕКОДИРОВАНИЯ сообщения
decode_msg() {
	local msg=$1

	# Расшифровка строки
	msg=$(echo "$msg" | rev)

	echo "$msg"
}
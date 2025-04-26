#!/bin/bash

# Директория с логами (куда пишем)
LOG_DIR="./logs"

# Директория с сообщениями (откуда читаем)
MSG_DIR="./messages"

# Чистка логов и сообщений
if [ -n "$(ls -A $MSG_DIR)" ]; then
    rm -rf $MSG_DIR/*
fi
if [ -n "$(ls -A $LOG_DIR)" ]; then
    rm -rf $LOG_DIR/*
fi

# Логи всей системы
LOG_COMPLEX="$LOG_DIR/complex.txt"

# Логи отдельных объектов
LOG_RLS1="$LOG_DIR/RLS1.txt"
LOG_RLS2="$LOG_DIR/RLS2.txt"
LOG_RLS3="$LOG_DIR/RLS3.txt"

LOG_SPRO="$LOG_DIR/SPRO.txt"

LOG_ZRDN1="$LOG_DIR/ZRDN1.txt"
LOG_ZRDN2="$LOG_DIR/ZRDN2.txt"
LOG_ZRDN3="$LOG_DIR/ZRDN3.txt"

> $LOG_COMPLEX
> $LOG_RLS1
> $LOG_RLS2
> $LOG_RLS3
> $LOG_SPRO
> $LOG_ZRDN1
> $LOG_ZRDN2
> $LOG_ZRDN3

# Функция ДЕКОДИРОВАНИЯ сообщения
decode_msg() {
	local msg=$1

	# Расшифровка строки
	msg=$(echo "$msg" | rev)

	echo "$msg"
}

while :
do
    # Проходим по каждому сообщению
    for file in "$MSG_DIR"/*.txt; do
        # Проверка на существование сообщений
        if [[ -f "$file" ]]; then
            # Извлекаем имя файла без пути
            filename=$(basename "$file")
            
            # Разбиваем имя файла на ИСТОЧНИК и ВРЕМЯ
            IFS='_' read -r source time <<< "${filename%.txt}"

            # Читаем содержимое файла
            msg=$(<"$file")

            # Расшифровка
            msg=$( decode_msg "$msg" )

            # Перевод времени в читаемый формат
            time=$(($time / 1000000000))
            time=$(date -d @$time +"%Y-%m-%d %H:%M:%S")

            # Логи
            echo "$time $msg" >> $LOG_COMPLEX
            echo "$time $msg" >> "$LOG_DIR/$source"

            # Сообщение прочитали -> удаляем
            rm $MSG_DIR/$filename
        fi
    done
done
#!/bin/bash

# Функция для завершения фоновых процессов
cleanup() {
    echo "Отключение всех объектов..."
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null
    done
    wait
    echo "Оборона отключена"
}

# Скрипт запуска всех объектов в одном терминале
# Символ "$" - запуск в фоновом режиме

# Установка ловушки для SIGINT (CTRL+C)
trap cleanup INT

# Массив для хранения PIDs фоновых процессов
pids=()

bash KP.sh &
pids+=($!)  # Сохранение PID
echo "Коммандный пункт активен"

bash RLS1.sh &
pids+=($!)
bash RLS2.sh &
pids+=($!)
bash RLS3.sh &
pids+=($!)
echo "РЛС активны"

bash SPRO.sh &
pids+=($!)  
echo "СПРО активен"

bash ZRDN1.sh &
pids+=($!)
bash ZRDN2.sh &
pids+=($!)
bash ZRDN3.sh &
pids+=($!)
echo "ЗРДН активны"

# Ожидание завершения всех фоновых процессов
wait
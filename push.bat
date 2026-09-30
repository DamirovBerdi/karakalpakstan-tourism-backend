@echo off
chcp 65001 > nul
echo ==============================================
echo 🚀 Отправка БЭКЕНДА в GitHub (Push Backend)
echo ==============================================

set /p msg="Введите описание изменений (Enter = 'Update backend'): "
if "%msg%"=="" set msg=Update backend

git add .
git commit -m "%msg%"
git push origin main

pause

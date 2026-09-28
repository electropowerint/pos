@echo off
title NovaPOS Sync (MongoDB Atlas)
cd /d "%~dp0"
echo NovaPOS sync server start ho raha hai...
echo Window band karne se server ruk jayega.
echo.
node server.js
pause

@echo off
REM 얇은 런처 — Windows cmd. 로직은 전부 autoloop.py 단일 코어에 있다(이중화 금지).
python "%~dp0autoloop.py" %*

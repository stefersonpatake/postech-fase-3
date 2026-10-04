FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Aplica as correções de segurança publicadas depois da imagem base.
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Processo sem privilégios de root dentro do container.
RUN useradd --system --uid 10001 --no-create-home app
USER app

EXPOSE 8005

CMD gunicorn --bind 0.0.0.0:${PORT:-8005} app:app

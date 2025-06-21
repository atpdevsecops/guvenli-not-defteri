# SECURITY NOTES:
# - Bu imaj, güvenlik için root olmayan bir kullanıcı kullanır
# - Multi-stage build ile derleme araçları final imajdan çıkarılmıştır
# - Gereksiz paketler ve dosyalar temizlenmiştir
# - Konteyner sağlığı düzenli olarak kontrol edilir
# - PYTHONDONTWRITEBYTECODE ve PYTHONUNBUFFERED güvenlik için ayarlanmıştır
# - Hassas dizinler salt okunur yapılmıştır
# - Bağımlılıklar sabitlenmiştir (requirements.txt içinde)

# 1. Build aşaması
FROM python:3.10-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /build

# Derleme araçlarını kur
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libffi-dev musl-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# pip ve setuptools'u güncelle
RUN python -m pip install --upgrade pip setuptools wheel

# requirements.txt dosyasını kopyala ve bağımlılıkları yükle
COPY requirements.txt .
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /build/wheels -r requirements.txt

# 2. Final aşaması
FROM python:3.10-slim

# Güvenlik ve optimizasyon için çevresel değişkenler
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV APP_ENV=production
ENV APP_DEBUG=false
ENV APP_PORT=5000

# Güvenlik için root olmayan kullanıcı oluştur
RUN groupadd -r appgroup && useradd --no-log-init -r -g appgroup appuser

WORKDIR /app

# Sadece gerekli paketleri kur
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Build aşamasından wheel dosyalarını kopyala ve yükle
COPY --from=builder /build/wheels /wheels
RUN pip install --no-cache --no-index --find-links=/wheels/ /wheels/* && \
    rm -rf /wheels

# Uygulama kodunu kopyala
COPY . .

# Loglar için dizin oluştur
RUN mkdir -p /app/logs

# Dosya izinlerini ve sahipliğini ayarla
RUN find /app -type d -exec chmod 555 {} \; && \
    find /app -type f -exec chmod 444 {} \; && \
    chmod -R 755 /app/logs && \
    chown -R appuser:appgroup /app

# Root olmayan kullanıcıya geç
USER appuser

# Uygulamanın çalışacağı portu belirt
EXPOSE 5000

# Konteyner sağlık kontrolü
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:5000/ || exit 1

# Uygulamayı Gunicorn ile çalıştır
CMD ["gunicorn", "--workers", "2", "--threads", "2", "--worker-class", "gthread", "--bind", "0.0.0.0:5000", "app:app"]

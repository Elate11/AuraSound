# AuraSound Max

Профессиональный аудиокомбайн и DSP-процессор для macOS. Позволяет выводить звук одновременно на несколько устройств (встроенные динамики MacBook и Bluetooth-колонки) с акустической компенсацией задержки, студийным 10-полосным эквалайзером, 3D Spatializer и аппаратным микшером громкости для каждого приложения на базе собственного драйвера CoreAudio HAL.

---

## Возможности

- **Одновременный вывод на несколько аудиоустройств**: Выводите системный звук синхронно на динамики Mac, Bluetooth-колонки, наушники и внешнюю акустику.
- **Акустическая автокалибровка задержки**: Алгоритм полосового GCC-PHAT через Apple Accelerate (vDSP) воспроизводит импульс розового шума, замеряет отклик через микрофон и убирает рассинхрон с точностью до 1 мс.
- **Аппаратный микшер приложений (SoundSource-архитектура)**: Собственный CoreAudio HAL аудиодрайвер перехватывает PCM-буферы процессов на уровне системы и независимо масштабирует громкость любых программ (включая Яндекс Музыку, Safari, Chrome, Telegram, игры).
- **10-полосный студийный эквалайзер**: Каскад IIR biquad-фильтров (от 32 Гц до 16 кГц) с нулевой задержкой, регуляторами Bass Punch, Vocal Boost и прозрачным лимитером против клиппинга.
- **3D Spatializer и расширение сцены**: Моделирование бинаурального кроссфида, ранних отражений помещения и регулировка расстояния виртуальной сцены.
- **Поддержка импульсов конволюции (IRS / WAV)**: Загрузка импульсов кабинетов и акустических пространств формата ViPER4Android и JamesDSP.
- **Спектроанализатор реального времени**: Высокоточный FFT-анализ частот прямо в интерфейсе строки меню.
- **Компактная работа из Menu Bar**: Приложение живет в строке меню macOS, не загромождая Dock.

---

## Архитектура системы

```
[ Любое приложение: Яндекс Музыка / Safari / Telegram ]
                     │
                     ▼
       [ CoreAudio HAL AudioServerPlugIn ]
        (индивидуальное масштабирование PCM сэмплов по PID)
                     │
                     ▼
           [ AuraSound Max DSP Движок ]
        (10-band EQ + 3D Spatial + Bass Boost + Limiter)
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
[ Динамики MacBook ]   [ Bluetooth-колонка ]
 (задержка: +120 мс)    (задержка: 0 мс)
          │                     │
          └──────────┬──────────┘
                     ▼
         Идеально сфазированный звук
```

---

## Требования

- macOS 13.0 (Ventura), 14.0 (Sonoma) или 15.0+ (Sequoia)
- Архитектура Apple Silicon (M1 / M2 / M3 / M4) или Intel x86_64
- Доступ к микрофону (требуется только на время акустической калибровки)

---

## Быстрый старт

### 1. Сборка и запуск приложения

```bash
git clone https://github.com/Elate11/AuraSound.git
cd AuraSound
./build_app.sh
open "/Applications/AuraSound Max.app"
```

Скрипт скомпилирует проект в Release-режиме, создаст бандл и установит его в директорию `/Applications/AuraSound Max.app`.

### 2. Установка аппаратного аудиодрайвера

Для независимой регулировки громкости закрытых приложений (Яндекс Музыка, игры) установите системный CoreAudio HAL драйвер:

```bash
cd AuraDriver
./build_and_install.sh
```

Скрипт соберет драйвер под Apple Silicon, подпишет его и скопирует в `/Library/Audio/Plug-Ins/HAL/`, после чего перезапустит аудиосервер `coreaudiod`.

---

## Как пользоваться

1. **Выбор вывода**: В «Системных настройках» -> «Звук» выберите виртуальный аудиодрайвер как устройство вывода по умолчанию.
2. **Подключение спикеров**: Откройте AuraSound Max из строки меню и отметьте галочками нужные колонки в блоке вывода.
3. **Автокалибровка**: Если между колонками слышно эхо, нажмите кнопку автокалибровки. Приложение подаст короткий тестовый сигнал и автоматически выровняет фазу.
4. **Микшер приложений**: В секции микшера передвигайте слайдеры громкости отдельных программ или выключайте звук кнопкой MUTE — звук регулируется аппаратно без переключения фокуса и задержек.

---

## Структура проекта

- [Sources/SoundBarBoost/RealAudioEngine.swift](file:///Users/aleksandr/AuraSound/Sources/SoundBarBoost/RealAudioEngine.swift) — ядро захвата аудио, кольцевые буферы задержки, DSP-цепочка и параллельные потоки вывода.
- [Sources/SoundBarBoost/CoreAudioDeviceManager.swift](file:///Users/aleksandr/AuraSound/Sources/SoundBarBoost/CoreAudioDeviceManager.swift) — обнаружение устройств CoreAudio, синхронизация мастер-громкости и автовыбор выходов.
- [Sources/SoundBarBoost/AppVolumeManager.swift](file:///Users/aleksandr/AuraSound/Sources/SoundBarBoost/AppVolumeManager.swift) — аппаратное управление громкостью приложений через вызовы драйвера `kAudioDeviceCustomPropertyAppVolumes`.
- [Sources/SoundBarBoost/AcousticAutoCalibrator.swift](file:///Users/aleksandr/AuraSound/Sources/SoundBarBoost/AcousticAutoCalibrator.swift) — алгоритм корреляционного анализа GCC-PHAT для автокалибровки задержки.
- [Sources/SoundBarBoost/MainPopoverView.swift](file:///Users/aleksandr/AuraSound/Sources/SoundBarBoost/MainPopoverView.swift) — интерфейс панели управления, спектроанализатор FFT и 2D-радар звуковой сцены.
- [AuraDriver/](file:///Users/aleksandr/AuraSound/AuraDriver/) — исходный код C++ CoreAudio HAL AudioServerPlugIn драйвера.
- [build_app.sh](file:///Users/aleksandr/AuraSound/build_app.sh) — скрипт сборки и установки приложения в `/Applications`.

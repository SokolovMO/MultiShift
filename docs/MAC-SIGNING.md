# Подпись MultiShift

Текущий выпуск не требует Apple Developer и не нотарифицирован Apple.
Приложение получает ad-hoc подпись; ZIP и лента Sparkle — Ed25519 подпись постоянным
локальным ключом. Подробности: [DISTRIBUTION.md](DISTRIBUTION.md).

Платная подпись Developer ID может быть добавлена позже. Сейчас Apple ID, p12,
app-specific password и Apple Team ID не нужны ни сборке, ни CI, ни публикации.

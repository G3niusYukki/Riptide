# Translation Guide / 翻译指南

## Supported Languages / 支持的语言

Riptide currently supports 7 languages plus system auto-detection:

| Language | Code | Status |
|----------|------|--------|
| System (Auto) | system | ✅ |
| English | en | ✅ |
| 简体中文 (Chinese Simplified) | zh-Hans | ✅ |
| 日本語 (Japanese) | ja | ✅ |
| Русский (Russian) | ru | ✅ |
| Español (Spanish) | es | ✅ |
| 한국어 (Korean) | ko | ✅ |
| فارسی (Persian) | fa | ✅ |

## How to Contribute / 如何贡献翻译

### Adding a New Language / 添加新语言

1. Fork the repository
2. Create a new `.lproj` directory: `Sources/RiptideApp/Localization/<language-code>.lproj/`
3. Copy `en.lproj/Localizable.strings` as a template
4. Translate all string values
5. Add the new language to `AppLanguage` enum in `Sources/RiptideApp/Localization/Localized.swift`
6. Update `Resources/Localizable.xcstrings` with the new language translations
7. Submit a Pull Request

### Localization Files Structure / 本地化文件结构

```
Sources/RiptideApp/Localization/
├── Localized.swift                      # Localized string keys enum
├── LocalizationManager.swift            # Localization manager class
├── en.lproj/
│   └── Localizable.strings              # English translations
├── ja.lproj/
│   └── Localizable.strings              # Japanese translations
├── ru.lproj/
│   └── Localizable.strings              # Russian translations
├── zh-Hans.lproj/
│   └── Localizable.strings              # Chinese Simplified translations
└── ... (other languages)

Resources/
└── Localizable.xcstrings                # Xcode String Catalog (source of truth)
```

### Translation Standards / 翻译规范

- **Consistency**: Maintain consistent terminology throughout the app
- **Brevity**: Keep UI text concise to avoid layout issues
- **Context**: Consider the context where strings appear in the UI
- **Testing**: Verify translations in the actual app UI

### Priority Translations / 优先翻译

High priority areas for translation:
1. Tab names (proxy, config, traffic, rules, logs)
2. Common actions (save, delete, add, edit, cancel)
3. Error messages
4. Menu bar items

## Language-Specific Notes / 语言特定说明

### Japanese / 日本語翻译者须知

- Use polite form (です/ます調) for UI text
- Keep expressions short for UI elements
- Technical terms can remain in English if commonly used in Japanese IT
- Example: "Proxy" → "プロキシ", "Config" → "設定"

### Russian / 俄语翻译者须知

- Pay attention to noun declension (cases)
- Keep UI text concise due to space constraints
- Follow Russian IT community conventions for technical terms
- Example: "Proxy" → "Прокси", "Settings" → "Настройки"

### Chinese Simplified / 简体中文翻译者须知

- Use concise expressions suitable for UI
- Technical terms should follow Chinese IT industry standards
- Example: "Proxy" → "代理", "Settings" → "设置"

## Testing Translations / 测试翻译

### Method 1: Xcode Scheme
1. In Xcode, select Product > Scheme > Edit Scheme
2. Under Run > Options, set Application Language to the target language
3. Run the app

### Method 2: Command Line
```bash
# Set language to Japanese
defaults write com.riptide Riptide AppleLanguages '(ja)'

# Set language to Russian
defaults write com.riptide Riptide AppleLanguages '(ru)'

# Reset to system default
defaults delete com.riptide Riptide AppleLanguages
```

### Method 3: In-App Language Selector
1. Open Riptide
2. Navigate to Settings/Config
3. Select Language option
4. Choose desired language from the list

## Future Languages / 未来计划添加的语言

- [ ] 繁體中文 (Chinese Traditional) - zh-Hant
- [ ] Deutsch (German) - de
- [ ] Français (French) - fr
- [ ] Português (Portuguese) - pt
- [ ] Italiano (Italian) - it
- [ ] Türkçe (Turkish) - tr
- [ ] العربية (Arabic) - ar

## Translation Checklist / 翻译检查清单

Before submitting a translation PR:

- [ ] All keys from `en.lproj/Localizable.strings` are translated
- [ ] No placeholder text remains (e.g., "TODO", "TRANSLATE")
- [ ] Special characters are properly escaped (quotes, backslashes)
- [ ] String length is reasonable for UI display
- [ ] Tested in the app UI
- [ ] `AppLanguage` enum updated (if adding new language)
- [ ] `Localizable.xcstrings` updated (if adding new language)

## Contact / 联系方式

For translation-related questions or discussions:
- Open an issue with the `translation` label
- Join our community discussions

---

## Quick Reference: Key Terms / 关键术语速查

| English | 简体中文 | 日本語 | Русский |
|---------|----------|--------|---------|
| Proxy | 代理 | プロキシ | Прокси |
| Config | 配置 | 設定 | Настройки |
| Subscription | 订阅 | サブスクリプション | Подписка |
| Connection | 连接 | 接続 | Подключение |
| Rule | 规则 | ルール | Правило |
| Traffic | 流量 | トラフィック | Трафик |
| Node | 节点 | ノード | Узел |
| Latency | 延迟 | 遅延 | Задержка |
| Upload | 上传 | アップロード | Отправка |
| Download | 下载 | ダウンロード | Загрузка |
| Save | 保存 | 保存 | Сохранить |
| Delete | 删除 | 削除 | Удалить |
| Edit | 编辑 | 編集 | Редактировать |
| Cancel | 取消 | キャンセル | Отмена |
| Add | 添加 | 追加 | Добавить |
| Close | 关闭 | 閉じる | Закрыть |

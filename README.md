<p align="center"><img src="hidden/Assets.xcassets/AppIcon.appiconset/icon_128@2x.png" width="128" alt="MenuHider"></p>

# MenuHider

macOS menü çubuğunu düzenleyen, Türkçe arayüzlü açık kaynaklı uygulama. [Hidden Bar](https://github.com/dwarvesf/hidden) temel alınarak geliştirilmiştir.

## İndir ve kullan

[Son sürümü indir](https://github.com/erhanulas/MenuHider/releases/latest). ZIP dosyasını açıp **MenuHider.app** uygulamasını **Uygulamalar** klasörüne taşıyın. macOS 13 ve üzeri, Apple Silicon ve Intel desteklenir.

Bu ilk dağıtım ad hoc imzalıdır; Apple Developer ID ile imzalanmış veya noter onaylı değildir. macOS ilk açılışta çalıştırmayı engelleyebilir. Kurumsal dağıtım için Developer ID imzalama ve noter onayı gerekir.

- Simgeleri göstermek/gizlemek için menü çubuğundaki sol oka tıklayın.
- Simgeler açıkken sınır çizgisi görünür. ⌘ tuşunu basılı tutarak çizgiyi okun hemen soluna yerleştirin; gizlenecek simgeler çizginin solunda olmalı.
- Gizliyken çizginin görüntüsü kaldırılır ve ok kullanılabilir kalır.
- macOS 27'de doğrudan gizleme kullanılır; harici monitörlerde geniş boşluk bırakılmaz. **Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik** bölümünde MenuHider izni gerekir. macOS sürümüne göre izin bölümü **Aygıt Denetimi ve Veri Erişimi** adıyla da görünebilir.
- Çizgi ile ok arasındaki simgeler görünür kalır. Gizleme uygulama bazındadır; aynı uygulamanın birden fazla simgesi birlikte yönetilir. macOS sistem simgeleri görünür kalır; bazı etkinlik simgeleri sürekli görünebilir.
- Oka sağ tıklayarak Ayarlar'a ulaşabilirsiniz.

## Güncelleme

**Ayarlar → Hakkında → Güncellemeleri Kontrol Et…** düğmesini kullanın. Yeni sürüm varsa Sparkle GitHub Releases üzerinden indirir, EdDSA imzasını doğrular ve **Yükle ve Yeniden Başlat** işlemiyle uygulamayı güncelleyip tekrar açar. Ayarlar korunur. Arka planda otomatik kontrol ve sistem profili gönderimi varsayılan olarak kapalıdır.

## Geliştirme

Xcode ve macOS 13+ gerekir. Paket bağımlılıkları Xcode tarafından indirilir.

```sh
xcodebuild -project 'Hidden Bar.xcodeproj' -scheme 'Hidden Bar' \
  -configuration Debug-Direct -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
```

Dağıtım ve güncelleme imzalama adımları: [docs/RELEASING.md](docs/RELEASING.md).

## Lisans ve kaynak

MIT lisansı. Orijinal Hidden Bar: Copyright © 2019 Dwarves Foundation. Kaynak geçmişi ve [LICENSE](LICENSE) korunmuştur. Güncelleme altyapısı [Sparkle](https://sparkle-project.org/), klavye kısayolları [HotKey](https://github.com/soffes/HotKey) kullanır. Yeni uygulama ikonu imagegen ile üretilmiştir.

# MenuHider sürüm yayımlama

Ürün kimliği `com.erhanulas.menuhider`, uygulama adı `MenuHider.app` olmalıdır. Eski `MenuHider Test.app` farklı kimlikli bir geliştirme kopyasıdır ve yayımlanan sürümlerle güncellenmez.

## İmza anahtarı

Sparkle 2.10.1 EdDSA özel anahtarı macOS giriş Anahtar Zinciri'nde `com.erhanulas.menuhider` hesabında tutulur. Yalnızca açık anahtar `hidden/Info.plist` içindeki `SUPublicEDKey` alanında bulunur. Özel anahtarı GitHub'a veya kaynak ağacına koymayın. Gelecek sürümleri imzalayabilmek için Anahtar Zinciri anahtarının güvenli yedeğini koruyun.

Projeyi ilk kez derledikten sonra araçlar `build/ReleaseData/SourcePackages/artifacts/sparkle/Sparkle/bin/` altında bulunur. Başka bir Mac'te yeni anahtar üretmek mevcut kurulumlara güncelleme gönderemez; mevcut anahtar güvenli yoldan taşınmalıdır.

## Paketleme

Proje dosyasındaki `MARKETING_VERSION` ve `CURRENT_PROJECT_VERSION` değerlerini artırın. Build numarası her zaman büyümelidir; Sparkle karşılaştırmayı bununla yapar.

```sh
python3 scripts/package-release.py 1.0.2 102 --notes release-notes.txt
```

Bu komut iki mimariyi (`arm64` ve `x86_64`) derler, kod imzasını doğrular, ZIP üretir ve Anahtar Zinciri'ndeki EdDSA anahtarıyla arşivi ve appcast'i imzalar. Çıktılar `dist/v1.0.2/` altındadır. Dizin varsa üzerine yazmaz. Sadece uygulama ZIP'i, `appcast.xml` ve `SHA256SUMS.txt` yayımlanmalıdır. Kaynak ve dağıtım `LICENSE` bilgisini korur.

Varsayılan kod imzası ad hoc'tur ve Apple noter onayı sağlamaz. Developer ID sertifikası edinildiğinde `--identity 'Developer ID Application: …'` kullanın; dağıtım arşivini imzalamadan önce noter onayı/stapling adımını da sürece ekleyin. Mevcut script noter onayı yapmaz.

## GitHub'a yayımlama

Önce build/test, imzalar ve temiz değişiklik kümesi kontrol edilir; kaynak commit'i ve sürüm etiketi aynı sürüme karşılık gelmelidir.

```sh
git push origin main
git tag v1.0.2
git push origin v1.0.2
gh release create v1.0.2 --repo erhanulas/MenuHider --verify-tag --draft \
  --title 'MenuHider 1.0.2' --notes-file release-notes.txt \
  dist/v1.0.2/MenuHider-1.0.2.zip dist/v1.0.2/appcast.xml dist/v1.0.2/SHA256SUMS.txt
# İndirme ve imzaları denetledikten sonra:
gh release edit v1.0.2 --repo erhanulas/MenuHider --draft=false --latest
```

Uygulamanın sabit besleme adresi:
`https://github.com/erhanulas/MenuHider/releases/latest/download/appcast.xml`

Her kontrol, GitHub latest yönlendirmesinin aynı uygulama oturumunda eski sürümde kalmasını önlemek için besleme adresine rastgele bir `check` parametresi ekler. İmzalı içerik ve arşiv adresleri değişmez.

Appcast her sürümün kendi etiketli ZIP adresini içerir. `generate_appcast` sonrasında appcast dosyasını elle değiştirmeyin; besleme imzası geçersiz olur. Önce tüm dosyaları draft release'e yükleyin, ardından release'i yayınlayın; böylece uygulama eksik paketli bir besleme görmez.

## Gerçek güncelleme kontrolü

Uygulamalar klasörüne önceki sürümü kurun. Hakkında ekranındaki düğmeyle GitHub beslemesini kontrol edin, yeni sürümü indirip yükleyin ve yeniden açılan uygulamanın yeni sürüm/build numarasını doğrulayın. Aynı sürümde tekrar kontrolün “güncel” sonucu verdiğini kontrol edin. Ayarlar ve menü çubuğu yerleşimi korunmalıdır. Test sürümünü aynı anda açık bırakmayın.

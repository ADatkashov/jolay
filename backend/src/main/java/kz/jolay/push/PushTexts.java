package kz.jolay.push;

import java.util.Map;

/** Localised push copy (kk/ru/en) for the notification types the platform emits. Unknown types get a generic text. */
final class PushTexts {
    private PushTexts() {}
    record Text(String title, String body) {}

    private static final Map<String, Map<String, Text>> T = Map.ofEntries(
        Map.entry("RIDE_OFFER", Map.of("kk", new Text("Жаңа тапсырыс", "Жолаушы жақын жерде. Қабылдауға 15 секунд бар."), "ru", new Text("Новый заказ", "Пассажир рядом. На принятие 15 секунд."), "en", new Text("New order", "A passenger is nearby. You have 15 seconds to accept."))),
        Map.entry("DRIVER_ACCEPTED", Map.of("kk", new Text("Жүргізуші табылды", "Жүргізуші сізге қарай келе жатыр."), "ru", new Text("Водитель найден", "Водитель едет к вам."), "en", new Text("Driver found", "Your driver is on the way."))),
        Map.entry("DRIVER_ARRIVING", Map.of("kk", new Text("Жүргізуші жолда", "Көлік сізге қарай келе жатыр."), "ru", new Text("Водитель в пути", "Машина едет к вам."), "en", new Text("Driver on the way", "Your car is heading to you."))),
        Map.entry("DRIVER_ARRIVED", Map.of("kk", new Text("Жүргізуші келді", "Көлік күтіп тұр."), "ru", new Text("Водитель приехал", "Машина ждёт вас."), "en", new Text("Driver has arrived", "Your car is waiting."))),
        Map.entry("RIDE_STARTED", Map.of("kk", new Text("Сапар басталды", "Жақсы жол!"), "ru", new Text("Поездка началась", "Счастливого пути!"), "en", new Text("Trip started", "Have a safe trip."))),
        Map.entry("RIDE_COMPLETED", Map.of("kk", new Text("Сапар аяқталды", "Сапарды бағалаңыз."), "ru", new Text("Поездка завершена", "Оцените поездку."), "en", new Text("Trip completed", "Please rate your trip."))),
        Map.entry("RIDE_EXPIRED", Map.of("kk", new Text("Жүргізуші табылмады", "Қайта көріңіз."), "ru", new Text("Водитель не найден", "Попробуйте ещё раз."), "en", new Text("No driver found", "Please try again."))),
        Map.entry("RIDE_CANCELLED", Map.of("kk", new Text("Сапар бас тартылды", "Тапсырыс жойылды."), "ru", new Text("Поездка отменена", "Заказ отменён."), "en", new Text("Trip cancelled", "The order was cancelled."))),
        Map.entry("DRIVER_CANCELLED", Map.of("kk", new Text("Жүргізуші бас тартты", "Жаңа жүргізуші іздеудеміз."), "ru", new Text("Водитель отменил", "Ищем нового водителя."), "en", new Text("Driver cancelled", "We are finding another driver."))),
        Map.entry("PAYMENT_STATUS_UPDATED", Map.of("kk", new Text("Төлем жаңартылды", "Төлем күйін қараңыз."), "ru", new Text("Статус оплаты", "Проверьте статус оплаты."), "en", new Text("Payment update", "Check your payment status."))),
        Map.entry("VERIFICATION_STATUS", Map.of("kk", new Text("Тексеру нәтижесі", "Аккаунт күйі өзгерді."), "ru", new Text("Результат проверки", "Статус аккаунта изменился."), "en", new Text("Verification update", "Your account status changed."))),
        Map.entry("PAYOUT_PAID", Map.of("kk", new Text("Төлем жасалды", "Сұранылған сома аударылды."), "ru", new Text("Выплата произведена", "Запрошенная сумма переведена."), "en", new Text("Payout sent", "The requested amount was transferred."))),
        Map.entry("PAYOUT_REJECTED", Map.of("kk", new Text("Төлем қабылданбады", "Сома әмияныңызға қайтарылды."), "ru", new Text("Выплата отклонена", "Сумма возвращена на кошелёк."), "en", new Text("Payout rejected", "The amount was returned to your wallet."))),
        Map.entry("SUPPORT_MESSAGE", Map.of("kk", new Text("Қолдау қызметінен хабарлама", "Жаңа жауап бар."), "ru", new Text("Сообщение от поддержки", "Есть новый ответ."), "en", new Text("Message from support", "You have a new reply."))),
        Map.entry("REFERRAL_REWARD", Map.of("kk", new Text("Бонус есептелді", "Достарды шақырғаныңыз үшін әмиянға бонус түсті."), "ru", new Text("Бонус начислен", "Бонус за приглашение зачислен на кошелёк."), "en", new Text("Bonus received", "Your referral bonus has been added to your wallet."))),
        Map.entry("INCIDENT_CREATED", Map.of("kk", new Text("Жаңа оқиға", "Назар аударуды қажет етеді."), "ru", new Text("Новый инцидент", "Требует внимания."), "en", new Text("New incident", "Needs attention."))),
        Map.entry("DELIVERY_OFFER", Map.of("kk", new Text("Жаңа жеткізу", "Жақын жерде жаңа жөнелтім бар."), "ru", new Text("Новая доставка", "Рядом новая посылка."), "en", new Text("New delivery", "A parcel is waiting nearby."))),
        Map.entry("DELIVERY_STATUS", Map.of("kk", new Text("Жеткізу жаңартылды", "Жөнелтім күйі өзгерді."), "ru", new Text("Статус доставки", "Статус посылки изменился."), "en", new Text("Delivery update", "Your parcel status changed."))));

    static Text of(String type, String locale) {
        Map<String, Text> m = T.get(type);
        String l = locale == null ? "kk" : locale;
        if (m != null) return m.getOrDefault(l, m.get("en"));
        return switch (l) { case "kk" -> new Text("JOLAY", "Жаңа хабарлама"); case "ru" -> new Text("JOLAY", "Новое уведомление"); default -> new Text("JOLAY", "New notification"); };
    }
}

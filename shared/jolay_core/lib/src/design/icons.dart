import 'package:flutter/material.dart';

/// Semantic icon names → one rounded Material icon each. Screens use these, never raw `Icons.*`,
/// so the icon language stays consistent and can be swapped in one place.
abstract final class AppIcons {
  // Services
  static const ride = Icons.local_taxi_rounded;
  static const order = Icons.shopping_bag_rounded;
  static const send = Icons.inventory_2_rounded;
  // Navigation
  static const home = Icons.home_rounded;
  static const homeOutlined = Icons.home_outlined;
  static const activity = Icons.receipt_long_rounded;
  static const activityOutlined = Icons.receipt_long_outlined;
  static const wallet = Icons.account_balance_wallet_rounded;
  static const walletOutlined = Icons.account_balance_wallet_outlined;
  static const profile = Icons.person_rounded;
  static const profileOutlined = Icons.person_outline_rounded;
  static const earnings = Icons.payments_rounded;
  static const earningsOutlined = Icons.payments_outlined;
  static const map = Icons.map_rounded;
  static const mapOutlined = Icons.map_outlined;
  // Actions
  static const search = Icons.search_rounded;
  static const back = Icons.arrow_back_rounded;
  static const close = Icons.close_rounded;
  static const chevron = Icons.chevron_right_rounded;
  static const add = Icons.add_rounded;
  static const edit = Icons.edit_outlined;
  static const delete = Icons.delete_outline_rounded;
  static const check = Icons.check_rounded;
  static const checkCircle = Icons.check_circle_rounded;
  static const refresh = Icons.refresh_rounded;
  static const call = Icons.call_rounded;
  static const message = Icons.chat_bubble_outline_rounded;
  static const share = Icons.ios_share_rounded;
  static const navigate = Icons.navigation_rounded;
  static const myLocation = Icons.my_location_rounded;
  static const locationOff = Icons.location_off_rounded;
  static const pin = Icons.location_on_rounded;
  static const flag = Icons.flag_rounded;
  static const history = Icons.history_rounded;
  static const bookmark = Icons.bookmark_rounded;
  static const star = Icons.star_rounded;
  static const starOutlined = Icons.star_outline_rounded;
  static const sos = Icons.warning_amber_rounded;
  static const shield = Icons.shield_outlined;
  static const gift = Icons.card_giftcard_rounded;
  static const support = Icons.support_agent_rounded;
  static const language = Icons.language_rounded;
  static const document = Icons.description_outlined;
  static const privacy = Icons.privacy_tip_outlined;
  static const info = Icons.info_outline_rounded;
  static const logout = Icons.logout_rounded;
  static const car = Icons.directions_car_filled_rounded;
  static const time = Icons.schedule_rounded;
  static const offline = Icons.cloud_off_rounded;
  static const upload = Icons.upload_file_rounded;
  static const hourglass = Icons.hourglass_top_rounded;
  static const block = Icons.block_rounded;
  static const cash = Icons.payments_outlined;
  static const card = Icons.credit_card_rounded;
  static const store = Icons.storefront_rounded;
  static const cart = Icons.shopping_cart_outlined;
  static const bike = Icons.delivery_dining_rounded;
  static const person = Icons.person_rounded;
  static const seat = Icons.airline_seat_recline_normal_rounded;
}

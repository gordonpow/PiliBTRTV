import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../services/auth_service.dart';

class VipAvatarBadge extends StatelessWidget {
  final Widget child;
  final double size; // 頭像的總大小 (寬/高)

  const VipAvatarBadge({super.key, required this.child, required this.size});

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isVip) {
      return child;
    }

    // Badge 的大小相對於頭像大小的比例
    final badgeSize = size * 0.35;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              color: const Color(0xFFFB7299), // B站粉
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 1.5, // 白色描邊
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '大',
              style: TextStyle(
                color: Colors.white,
                fontSize: badgeSize * 0.7, // 字號根據 badge 大小動態調整
                fontWeight: FontWeight.bold,
                height: 1.1, // 微調行高以垂直居中
              ),
            ),
          ),
        ),
      ],
    );
  }
}

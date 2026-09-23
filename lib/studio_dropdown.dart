import 'package:flutter/material.dart';
import 'studio_widgets.dart';

class StudioDropdown<T> extends StatelessWidget {
  const StudioDropdown({
    super.key,
    this.value,
    this.hint,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
    this.underline,
    this.padding,
    this.borderRadius,
    this.style,
  });
  final T? value;
  final Widget? hint, underline;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Material(
    color: StudioColors.raised,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: StudioColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: DropdownButton<T>(
      value: value,
      hint: hint,
      items: items,
      onChanged: onChanged,
      isExpanded: isExpanded,
      underline: const SizedBox(),
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
      borderRadius: BorderRadius.circular(8),
      dropdownColor: StudioColors.raised,
      menuMaxHeight: 360,
      itemHeight: 48,
      style:
          style ??
          TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            height: 1.2,
            color: StudioColors.text,
          ),
      icon: Icon(Icons.expand_more, size: 20, color: StudioColors.muted),
      focusColor: StudioColors.hover,
    ),
  );
}

class StudioDropdownField<T> extends DropdownButtonFormField<T> {
  StudioDropdownField({
    super.key,
    super.initialValue,
    required super.items,
    required super.onChanged,
    super.isExpanded = true,
    super.decoration,
  }) : super(
         dropdownColor: StudioColors.raised,
         borderRadius: BorderRadius.circular(8),
         menuMaxHeight: 360,
         style: TextStyle(
           fontFamily: 'Pretendard',
           fontSize: 16,
           height: 1.2,
           color: StudioColors.text,
         ),
       );
}

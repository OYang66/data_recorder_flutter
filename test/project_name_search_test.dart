import 'package:data_recorder/features/main/project_name_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filterProjectNames', () {
    const projectNames = ['中海489项目', '成都麓湖生态城C7项目', '  中海489项目  ', ''];

    test('按中文项目名进行包含匹配', () {
      expect(filterProjectNames(projectNames, '中海'), ['中海489项目']);
      expect(filterProjectNames(projectNames, '生态城'), ['成都麓湖生态城C7项目']);
    });

    test('忽略关键词空格和英文大小写', () {
      expect(filterProjectNames(projectNames, ' c7 '), ['成都麓湖生态城C7项目']);
    });

    test('空关键词返回去重、去空的完整列表', () {
      expect(filterProjectNames(projectNames, '  '), [
        '中海489项目',
        '成都麓湖生态城C7项目',
      ]);
    });

    test('没有匹配项目时返回空列表', () {
      expect(filterProjectNames(projectNames, '不存在'), isEmpty);
    });
  });
}

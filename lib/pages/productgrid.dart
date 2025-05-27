import 'package:flutter/material.dart';
import 'package:gifthub/services/video_widget.dart';
import 'package:gifthub/themes/colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gifthub/pages/product_card.dart';
import 'package:gifthub/services/wishlist_service.dart';

enum PriceSortType {
  none,
  ascending,
  descending
}

class ResponsiveGrid extends StatefulWidget {
  final String searchQuery;
  final Function(Map<String, dynamic>)? onProductTap;

  const ResponsiveGrid({
    super.key,
    required this.searchQuery,
    this.onProductTap,
  });

  @override
  State<ResponsiveGrid> createState() => _ResponsiveGridState();
}

class _ResponsiveGridState extends State<ResponsiveGrid> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> colors = [];
  Map<int, List<Map<String, dynamic>>> categoryParameters = {};
  bool isLoading = true;
  PriceSortType currentSort = PriceSortType.none;
  int? selectedCategory;
  int? selectedParameter;
  int? selectedColor;

  final Map<PriceSortType, String> sortTypeNames = {
    PriceSortType.none: 'Без сортировки',
    PriceSortType.ascending: 'По возрастанию цены',
    PriceSortType.descending: 'По убыванию цены',
  };

  @override
  void initState() {
    super.initState();
    fetchCategories();
    fetchProducts();
    fetchColors();
  }

  Future<void> fetchCategories() async {
    try {
      final response = await supabase
          .from('ProductCategory')
          .select('ProductCategoryID, ProductCategoryName');

      setState(() {
        categories = response;
      });
    } catch (error) {
      print('Ошибка при загрузке категорий: $error');
    }
  }

  Future<void> fetchParametersForCategory(int categoryId) async {
    try {
      final response = await supabase
          .from('Parametr')
          .select('''
            ParametrID,
            ParametrName,
            Parametr,
            ParametrProduct!inner(
              ProductID,
              Quantity
            )
          ''')
          .eq('ParametrCategory', categoryId)
          .gt('ParametrProduct.Quantity', 0);

      setState(() {
        categoryParameters[categoryId] = response;
      });
    } catch (error) {
      print('Ошибка при загрузке параметров: $error');
    }
  }

  List<Map<String, dynamic>> get filteredProducts {
    List<Map<String, dynamic>> filtered = List.from(products);

    if (widget.searchQuery.isNotEmpty) {
      filtered = filtered.where((product) =>
      product['ProductName']?.toLowerCase()
          .contains(widget.searchQuery.toLowerCase()) ?? false
      ).toList();
    }

    // Фильтрация по цвету
    if (selectedColor != null) {
      filtered = filtered.where((product) {
        final productColors = product['ProductColor'] as List?;
        return productColors?.any((colorData) =>
        colorData['ColorParametr'] == selectedColor
        ) ?? false;
      }).toList();
    }


    if (selectedCategory != null) {
      filtered = filtered.where((product) =>
      product['ProductCategory'] == selectedCategory
      ).toList();

      if (selectedParameter != null) {
        filtered = filtered.where((product) {
          final parameters = product['ParametrProduct'] as List?;
          return parameters?.any((param) =>
          param['ParametrID'] == selectedParameter &&
              (param['Quantity'] ?? 0) > 0
          ) ?? false;
        }).toList();
      }
    }

    switch (currentSort) {
      case PriceSortType.ascending:
        filtered.sort((a, b) => (a['ProductCost'] as num)
            .compareTo(b['ProductCost'] as num));
        break;
      case PriceSortType.descending:
        filtered.sort((a, b) => (b['ProductCost'] as num)
            .compareTo(a['ProductCost'] as num));
        break;
      case PriceSortType.none:
        break;
    }

    return filtered;
  }

  Future<void> fetchColors() async {
    try {
      final response = await supabase
          .from('Parametr')
          .select('''
          ParametrID,
          ParametrName,
          Parametr,
          ProductColor!inner(
            Product!inner(
              ProductQuantity
            )
          )
        ''')
          .eq('ParametrName', 'Цвет')
          .gt('ProductColor.Product.ProductQuantity', 0)
          .order('Parametr');

      setState(() {
        // Удаление дубликатоы параметров
        final uniqueColors = <int, Map<String, dynamic>>{};
        for (var color in response) {
          uniqueColors[color['ParametrID']] = color;
        }
        colors = uniqueColors.values.toList();
      });
    } catch (error) {
      print('Ошибка при загрузке цветов: $error');
    }
  }

  Future<void> fetchProducts() async {
    try {
      setState(() {
        isLoading = true;
      });

      final response = await supabase
          .from('Product')
          .select('''
          ProductID,
          ProductName,
          ProductCost,
          ProductCategory,
          ProductQuantity,
          ProductPhoto(Photo),
          ParametrProduct(
            ParametrID,
            Quantity
          ),
          ProductColor(
            ColorParametr,
            Parametr(
              ParametrID,
              ParametrName,
              Parametr
            )
          )
        ''')
          .gt('ProductQuantity', 0);

      setState(() {
        products = response;
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        isLoading = false;
      });
      print('Ошибка при загрузке продуктов: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке продуктов: $error')),
      );
    }
  }

  bool isVideoUrl(String url) {
    final extensions = ['.mp4', '.mov', '.avi', '.wmv'];
    return extensions.any((ext) => url.toLowerCase().endsWith(ext));
  }

  Widget buildMediaWidget(String url) {
    if (isVideoUrl(url)) {
      return VideoPlayerScreen(
        videoUrl: url,
        isMuted: true,
      );
    }
    return Image.network(
      url,
      width: double.infinity,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.image_not_supported),
    );
  }

  void showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                'Фильтры',
                style: TextStyle(
                  color: darkGreen,
                  fontFamily: "segoeui",
                  fontWeight: FontWeight.w500,
                ),
              ),
              backgroundColor: Colors.white,
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Фильтр по цветам
                    if (colors.isNotEmpty) ...[
                      Text(
                        'Цвет:',
                        style: TextStyle(
                          color: darkGreen,
                          fontFamily: "segoeui",
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: backgroundBeige,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: selectedColor,
                          underline: Container(),
                          hint: Text(
                            'Выберите цвет',
                            style: TextStyle(
                              color: darkGreen,
                              fontFamily: "segoeui",
                            ),
                          ),
                          dropdownColor: backgroundBeige,
                          items: [
                            DropdownMenuItem<int>(
                              value: null,
                              child: Text(
                                'Все цвета',
                                style: TextStyle(
                                  color: darkGreen,
                                  fontFamily: "segoeui",
                                ),
                              ),
                            ),
                            ...colors.map((color) {
                              return DropdownMenuItem<int>(
                                value: color['ParametrID'],
                                child: Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      margin: EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(

                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                          width: 1,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        color['Parametr'],
                                        style: TextStyle(
                                          color: darkGreen,
                                          fontFamily: "segoeui",
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedColor = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(color: darkGreen.withOpacity(0.2)),
                      const SizedBox(height: 16),
                    ],

                    // Фильтр по категориям
                    Text(
                      'Категория:',
                      style: TextStyle(
                        color: darkGreen,
                        fontFamily: "segoeui",
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: backgroundBeige,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: selectedCategory,
                        underline: Container(),
                        hint: Text(
                          'Выберите категорию',
                          style: TextStyle(
                            color: darkGreen,
                            fontFamily: "segoeui",
                          ),
                        ),
                        dropdownColor: backgroundBeige,
                        items: [
                          DropdownMenuItem<int>(
                            value: null,
                            child: Text(
                              'Все категории',
                              style: TextStyle(
                                color: darkGreen,
                                fontFamily: "segoeui",
                              ),
                            ),
                          ),
                          ...categories.map((category) {
                            return DropdownMenuItem<int>(
                              value: category['ProductCategoryID'],
                              child: Text(
                                category['ProductCategoryName'],
                                style: TextStyle(
                                  color: darkGreen,
                                  fontFamily: "segoeui",
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedCategory = value;
                            selectedParameter = null;
                            if (value != null) {
                              fetchParametersForCategory(value);
                            }
                          });
                        },
                      ),
                    ),

                    // Параметры категории
                    if (selectedCategory != null &&
                        categoryParameters[selectedCategory]?.isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Параметры категории:',
                        style: TextStyle(
                          color: darkGreen,
                          fontFamily: "segoeui",
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: backgroundBeige,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: selectedParameter,
                          underline: Container(),
                          hint: Text(
                            'Выберите параметр',
                            style: TextStyle(
                              color: darkGreen,
                              fontFamily: "segoeui",
                            ),
                          ),
                          dropdownColor: backgroundBeige,
                          items: [
                            DropdownMenuItem<int>(
                              value: null,
                              child: Text(
                                'Все параметры',
                                style: TextStyle(
                                  color: darkGreen,
                                  fontFamily: "segoeui",
                                ),
                              ),
                            ),
                            ...categoryParameters[selectedCategory]!.map((parameter) {
                              return DropdownMenuItem<int>(
                                value: parameter['ParametrID'],
                                child: Text(
                                  '${parameter['ParametrName']}: ${parameter['Parametr']}',
                                  style: TextStyle(
                                    color: darkGreen,
                                    fontFamily: "segoeui",
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedParameter = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                // Кнопки действий
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          selectedCategory = null;
                          selectedParameter = null;
                          selectedColor = null;
                        });
                        Navigator.pop(context);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: darkGreen,
                      ),
                      child: Text(
                        'Сбросить',
                        style: TextStyle(
                          fontFamily: "segoeui",
                          fontSize: 16
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: darkGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Применить',
                        style: TextStyle(
                          fontFamily: "segoeui",
                          fontSize: 16
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 24),
              actionsPadding: EdgeInsets.fromLTRB(24, 0, 24, 16),
            );
          },
        );
      },
    ).then((_) {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Строка с сортировкой и фильтром
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: backgroundBeige,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: Stack(
                      children: [
                        Icon(Icons.filter_list, color: darkGreen),
                        if (selectedCategory != null || selectedColor != null)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: wishListIcon,
                                shape: BoxShape.circle,
                              ),
                              constraints: BoxConstraints(
                                minWidth: 8,
                                minHeight: 8,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onPressed: showFilterDialog,
                  ),
                ),
                Row(
                  children: [

                    Container(
                      decoration: BoxDecoration(
                        color: backgroundBeige,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: DropdownButton<PriceSortType>(
                        value: currentSort,
                        underline: Container(),
                        style: TextStyle(
                          color: darkGreen,
                          fontFamily: "segoeui",
                        ),
                        dropdownColor: backgroundBeige,
                        items: PriceSortType.values.map((PriceSortType type) {
                          return DropdownMenuItem<PriceSortType>(
                            value: type,
                            child: Text(
                              sortTypeNames[type]!,
                              style: TextStyle(color: darkGreen),
                            ),
                          );
                        }).toList(),
                        onChanged: (PriceSortType? newValue) {
                          if (newValue != null) {
                            setState(() {
                              currentSort = newValue;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Содержимое (загрузка, пустой список или сетка товаров)
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : filteredProducts.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: darkGreen.withOpacity(0.5),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Товары не найдены',
                    style: TextStyle(
                      color: darkGreen,
                      fontFamily: "segoeui",
                      fontSize: 18,
                    ),
                  ),
                  if (selectedCategory != null || selectedColor != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            selectedCategory = null;
                            selectedParameter = null;
                            selectedColor = null;
                          });
                        },
                        child: Text(
                          'Сбросить фильтры',
                          style: TextStyle(
                            color: darkGreen,
                            fontFamily: "segoeui",
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
                : LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = (constraints.maxWidth / 150)
                    .floor()
                    .clamp(2, 6);
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.8,
                  ),
                  padding: EdgeInsets.only(bottom: 90, top: 0),
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = filteredProducts[index];
                    final imageUrl = product['ProductPhoto']?.isNotEmpty ?? false
                        ? product['ProductPhoto'][0]['Photo']
                        : 'https://picsum.photos/200/300';

                    return InkWell(
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          '/product/${product['ProductID']}',
                          arguments: product,
                        );
                      },
                      child: Card(
                        elevation: 0,
                        color: backgroundBeige,
                        borderOnForeground: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Stack(
                          children: [
                            Column(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.all(
                                        Radius.circular(10)),
                                    child: buildMediaWidget(imageUrl),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Column(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          product['ProductName'] ??
                                              'Без названия',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: darkGreen,
                                            fontFamily: "segoeui",
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Flexible(
                                        child: Text(
                                          '${product['ProductCost']} ₽',
                                          style: TextStyle(
                                            color: darkGreen,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: "segoeui",
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Positioned(
                              right: 5,
                              child: StatefulBuilder(
                                builder: (context, setStateIcon) {
                                  final isInWishlist = ValueNotifier<bool>(false);
                                  final productId = product['ProductID'];
                                  checkInWishlist(productId).then((value) {
                                    isInWishlist.value = value;
                                  });

                                  return ValueListenableBuilder<bool>(
                                    valueListenable: isInWishlist,
                                    builder: (context, value, _) {
                                      return IconButton(
                                        icon: Icon(
                                          value ? Icons.favorite : Icons.favorite_border,
                                          color: value ? wishListIcon : null,
                                        ),
                                        color: wishListIcon,
                                        onPressed: () {
                                          toggleWishlistService(
                                            context: context,
                                            productId: productId,
                                            isInWishlist: isInWishlist,
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
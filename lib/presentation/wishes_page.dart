import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../logic/wish_list_model.dart';
import '../widgets/wish_card.dart';

class WishesPage extends StatelessWidget {
  const WishesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 Provider 将数据逻辑注入，并在创建时立刻读取本地数据
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            '心愿便签',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            indicatorColor: Colors.pinkAccent,
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Text('我的心愿'),
              Text('心愿广场'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _MyWishesView(),
            _PublicWishesView(),
          ],
        ),
      ),
    );
  }
}

class _MyWishesView extends StatelessWidget {
  const _MyWishesView();

  @override
  Widget build(BuildContext context) {
    return Consumer<WishListModel>(
      builder: (context, model, child) {
        if (model.isLoading && model.wishes.isEmpty) {
          return const Center(child: CircularProgressIndicator(),);
        }

        if (model.wishes.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => model.syncAndRefresh(),
            child: ListView(
              children: [
                SizedBox(height: 150,),
                Center(
                  child: Text(
                    '还没有心愿哦，点击下方 + 号留下你的心愿吧~!',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => model.syncAndRefresh(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            itemCount: model.wishes.length + 1,
            itemBuilder: (context, index) {
              if (index == model.wishes.length) {
                return const _ListFooter();
              }
              return WishCard(wish: model.wishes[index]);
            },
          ),
        );
      },
    );
  }
}

class _PublicWishesView extends StatelessWidget {
  const _PublicWishesView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '广场功能即将上线...',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 40, height: 1, color: Colors.grey.shade300),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '--- 已经到底啦 ---',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Container(width: 40, height: 1, color: Colors.grey.shade300),
        ],
      ),
    );
  }
}
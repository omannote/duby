<?php
session_start();
if (!isset($_SESSION['user'])) {
    header('Location: /login.php');
    exit;
}

require_once __DIR__ . '/../config/db.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: /pos.php');
    exit;
}

$customerId = $_POST['customer_id'] ?? null;
$itemsJson  = $_POST['items'] ?? '';
$items = json_decode($itemsJson, true);

if (!$customerId || !$items || !is_array($items)) {
    die('Invalid order data');
}

$pdo->beginTransaction();
try {
    // Generate unique order number
    $stmt = $pdo->query("SELECT CONCAT('ORD', LPAD(IFNULL(MAX(id)+1,1), 3, '0')) AS next_order_number FROM orders");
    $orderNumber = $stmt->fetch()['next_order_number'];

    $total = 0;
    foreach ($items as $item) {
        $total += $item['price'] * $item['qty'];
    }

    $insertOrder = $pdo->prepare('INSERT INTO orders (order_number, customer_id, branch_id, user_id, status, total, payment_status) VALUES (?, ?, ?, ?, \"received\", ?, \"unpaid\")');
    $insertOrder->execute([$orderNumber, $customerId, $_SESSION['user']['branch_id'], $_SESSION['user']['id'], $total]);

    $orderId = $pdo->lastInsertId();

    $insertItem = $pdo->prepare('INSERT INTO order_items (order_id, service_id, quantity, price) VALUES (?, ?, ?, ?)');
    foreach ($items as $item) {
        $insertItem->execute([$orderId, $item['id'], $item['qty'], $item['price']]);
    }

    $pdo->commit();
    header('Location: /pos.php?success=1&order=' . urlencode($orderNumber));
    exit;
} catch (Exception $e) {
    $pdo->rollBack();
    die('Error processing order');
}

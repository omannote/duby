<?php
session_start();
if (!isset($_SESSION['user'])) {
    header('Location: /login.php');
    exit;
}
require_once __DIR__ . '/../config/db.php';

$stmt = $pdo->query('SELECT COUNT(*) AS customer_count FROM customers');
$customerCount = $stmt->fetch()['customer_count'];

$stmt = $pdo->query('SELECT COUNT(*) AS order_count FROM orders');
$orderCount = $stmt->fetch()['order_count'];
?>
<?php include 'includes/header.php'; ?>
<h3>Dashboard</h3>
<div class="row">
    <div class="col-md-6">
        <div class="card mb-3">
            <div class="card-body">
                <h5 class="card-title">Total Customers</h5>
                <p class="card-text display-6"><?= $customerCount ?></p>
            </div>
        </div>
    </div>
    <div class="col-md-6">
        <div class="card mb-3">
            <div class="card-body">
                <h5 class="card-title">Total Orders</h5>
                <p class="card-text display-6"><?= $orderCount ?></p>
            </div>
        </div>
    </div>
</div>
<?php include 'includes/footer.php'; ?>

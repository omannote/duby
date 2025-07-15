<?php
session_start();
if (!isset($_SESSION['user'])) {
    header('Location: /login.php');
    exit;
}

require_once __DIR__ . '/../config/db.php';

// Fetch services
$serviceStmt = $pdo->query('SELECT id, name, price FROM services');
$services = $serviceStmt->fetchAll();

// Fetch customers
$customerStmt = $pdo->query('SELECT id, name FROM customers ORDER BY name');
$customers = $customerStmt->fetchAll();
?>
<?php include 'includes/header.php'; ?>
<h3>Point of Sale</h3>
<?php if (isset($_GET['success'])): ?>
    <div class="alert alert-success">Order <?= htmlspecialchars($_GET['order'] ?? '') ?> created successfully.</div>
<?php endif; ?>
<div class="row">
    <div class="col-md-4">
        <h5>Services</h5>
        <div class="list-group" id="service-list">
            <?php foreach ($services as $service): ?>
            <button type="button" class="list-group-item list-group-item-action" data-id="<?= $service['id'] ?>" data-name="<?= htmlspecialchars($service['name']) ?>" data-price="<?= $service['price'] ?>">
                <?= htmlspecialchars($service['name']) ?> - <?= number_format($service['price'], 3) ?> OMR
            </button>
            <?php endforeach; ?>
        </div>
    </div>
    <div class="col-md-8">
        <form id="pos-form" method="POST" action="process_order.php">
            <div class="mb-3">
                <label for="customer" class="form-label">Customer</label>
                <select class="form-select" id="customer" name="customer_id" required>
                    <option value="">Select Customer</option>
                    <?php foreach ($customers as $customer): ?>
                    <option value="<?= $customer['id'] ?>"><?= htmlspecialchars($customer['name']) ?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <table class="table" id="cart-table">
                <thead>
                    <tr>
                        <th>Service</th>
                        <th>Qty</th>
                        <th>Price</th>
                        <th>Total</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody></tbody>
            </table>
            <div class="d-flex justify-content-end">
                <h4>Total: <span id="grand-total">0.000</span> OMR</h4>
            </div>
            <input type="hidden" name="items" id="items-input">
            <button type="submit" class="btn btn-primary mt-3">Submit Order</button>
        </form>
    </div>
</div>

<script>
const serviceButtons = document.querySelectorAll('#service-list button');
const cartTableBody = document.querySelector('#cart-table tbody');
const grandTotalSpan = document.getElementById('grand-total');
const itemsInput = document.getElementById('items-input');
let cart = {};

function renderCart() {
    cartTableBody.innerHTML = '';
    let grandTotal = 0;
    Object.values(cart).forEach(item => {
        const row = document.createElement('tr');
        const total = item.price * item.qty;
        grandTotal += total;
        row.innerHTML = `
            <td>${item.name}</td>
            <td><input type="number" min="1" value="${item.qty}" data-id="${item.id}" class="form-control qty-input" style="width:80px"></td>
            <td>${item.price.toFixed(3)}</td>
            <td>${total.toFixed(3)}</td>
            <td><button type="button" class="btn btn-sm btn-danger remove-btn" data-id="${item.id}">X</button></td>
        `;
        cartTableBody.appendChild(row);
    });
    grandTotalSpan.textContent = grandTotal.toFixed(3);
    itemsInput.value = JSON.stringify(cart);
}

serviceButtons.forEach(btn => {
    btn.addEventListener('click', () => {
        const id = btn.dataset.id;
        if (!cart[id]) {
            cart[id] = {
                id: parseInt(id),
                name: btn.dataset.name,
                price: parseFloat(btn.dataset.price),
                qty: 1
            };
        } else {
            cart[id].qty += 1;
        }
        renderCart();
    });
});

cartTableBody.addEventListener('click', e => {
    if (e.target.classList.contains('remove-btn')) {
        const id = e.target.dataset.id;
        delete cart[id];
        renderCart();
    }
});

cartTableBody.addEventListener('change', e => {
    if (e.target.classList.contains('qty-input')) {
        const id = e.target.dataset.id;
        const qty = parseInt(e.target.value) || 1;
        cart[id].qty = qty > 0 ? qty : 1;
        renderCart();
    }
});
</script>
<?php include 'includes/footer.php'; ?>

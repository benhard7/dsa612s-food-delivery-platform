// Statistics are computed on request from the three stored collections.

type Acc record {|
    int placed = 0;
    int cancelled = 0;
    int delivered = 0;
    float revenue = 0.0;
    map<int> itemQty = {};
|};

type DriverAcc record {|
    int count = 0;
    int minutes = 0;
|};

function round2(float v) returns float => float:round(v, 2);

function toRestaurantStats(string restaurantId, Acc acc) returns RestaurantStats {
    int kept = acc.placed - acc.cancelled;
    ItemCount[] items = [];
    foreach string itemName in acc.itemQty.keys() {
        items.push({name: itemName, qty: acc.itemQty.get(itemName)});
    }
    ItemCount[] sorted = from ItemCount i in items
        order by i.qty descending
        select i;
    ItemCount[] top = sorted.length() > 5 ? sorted.slice(0, 5) : sorted;
    float rate = acc.placed == 0 ? 0.0 : <float>acc.cancelled / <float>acc.placed;
    float average = kept == 0 ? 0.0 : acc.revenue / <float>kept;
    return {
        restaurantId: restaurantId,
        ordersPlaced: acc.placed,
        ordersCancelled: acc.cancelled,
        ordersDelivered: acc.delivered,
        cancellationRate: round2(rate),
        revenue: round2(acc.revenue),
        averageOrderValue: round2(average),
        topItems: top
    };
}

function computeRestaurantStats() returns RestaurantStats[]|error {
    PlacedOrder[] placed = check listPlaced();
    CancelledOrder[] cancelled = check listCancelled();
    CompletedDelivery[] done = check listDeliveries();

    map<boolean> cancelledIds = {};
    foreach CancelledOrder c in cancelled {
        cancelledIds[c.orderId] = true;
    }
    map<boolean> deliveredIds = {};
    foreach CompletedDelivery d in done {
        deliveredIds[d.orderId] = true;
    }

    map<Acc> byRestaurant = {};
    foreach PlacedOrder p in placed {
        Acc acc = {};
        Acc? existing = byRestaurant[p.restaurantId];
        if existing is Acc {
            acc = existing;
        }
        acc.placed += 1;
        if cancelledIds.hasKey(p.orderId) {
            acc.cancelled += 1;
        } else {
            acc.revenue += p.total;
            if deliveredIds.hasKey(p.orderId) {
                acc.delivered += 1;
            }
            foreach OrderItem it in p.items {
                int soFar = acc.itemQty[it.name] ?: 0;
                acc.itemQty[it.name] = soFar + it.qty;
            }
        }
        byRestaurant[p.restaurantId] = acc;
    }

    RestaurantStats[] result = [];
    foreach string restaurantId in byRestaurant.keys() {
        result.push(toRestaurantStats(restaurantId, byRestaurant.get(restaurantId)));
    }
    return from RestaurantStats s in result
        order by s.ordersPlaced descending
        select s;
}

function computeDeliveryStats() returns DeliveryStats|error {
    CompletedDelivery[] done = check listDeliveries();
    int totalMinutes = 0;
    int fastest = 0;
    int slowest = 0;
    boolean first = true;
    map<DriverAcc> byDriver = {};
    foreach CompletedDelivery d in done {
        totalMinutes += d.durationMinutes;
        if first || d.durationMinutes < fastest {
            fastest = d.durationMinutes;
        }
        if first || d.durationMinutes > slowest {
            slowest = d.durationMinutes;
        }
        first = false;
        DriverAcc acc = {};
        DriverAcc? existing = byDriver[d.driverId];
        if existing is DriverAcc {
            acc = existing;
        }
        acc.count += 1;
        acc.minutes += d.durationMinutes;
        byDriver[d.driverId] = acc;
    }

    DriverStats[] drivers = [];
    foreach string driverId in byDriver.keys() {
        DriverAcc acc = byDriver.get(driverId);
        drivers.push({
            driverId: driverId,
            deliveries: acc.count,
            averageMinutes: round2(<float>acc.minutes / <float>acc.count)
        });
    }
    DriverStats[] rankedDrivers = from DriverStats ds in drivers
        order by ds.deliveries descending
        select ds;

    int n = done.length();
    return {
        completed: n,
        averageMinutes: n == 0 ? 0.0 : round2(<float>totalMinutes / <float>n),
        fastestMinutes: fastest,
        slowestMinutes: slowest,
        drivers: rankedDrivers
    };
}

function computeOverview() returns Overview|error {
    RestaurantStats[] restaurants = check computeRestaurantStats();
    DeliveryStats deliveries = check computeDeliveryStats();
    int placed = 0;
    int cancelled = 0;
    int delivered = 0;
    float revenue = 0.0;
    foreach RestaurantStats r in restaurants {
        placed += r.ordersPlaced;
        cancelled += r.ordersCancelled;
        delivered += r.ordersDelivered;
        revenue += r.revenue;
    }
    return {
        restaurants: restaurants.length(),
        ordersPlaced: placed,
        ordersCancelled: cancelled,
        ordersDelivered: delivered,
        revenue: round2(revenue),
        deliveriesCompleted: deliveries.completed,
        averageDeliveryMinutes: deliveries.averageMinutes
    };
}

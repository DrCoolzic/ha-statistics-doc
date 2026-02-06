
# TODO NOT YET READY

## **Why Home Assistant (and Python apps) Use SQLAlchemy**

SQLAlchemy is a **database abstraction layer** that lets you:

1. **Write database-agnostic code** - Works with SQLite, MySQL, PostgreSQL, etc.
2. **Switch databases easily** - Change one config line, code stays the same
3. **Avoid SQL dialect hell** - SQLAlchemy translates to the right SQL dialect
4. **Use Pythonic syntax** - Write queries in Python instead of raw SQL strings

------

## **Example: The Same Query in Different Ways**

### **Raw SQL (Database-Specific) ❌**

**For SQLite:**

```python
import sqlite3

conn = sqlite3.connect('home-assistant_v2.db')
cursor = conn.execute("""
    SELECT datetime(start_ts, 'unixepoch', 'localtime') as hour, 
           mean, sum
    FROM statistics s
    JOIN statistics_meta sm ON s.metadata_id = sm.id
    WHERE sm.statistic_id = ?
""", ('sensor.linky_urms1',))
```

**For MariaDB:**

```python
import mysql.connector

conn = mysql.connector.connect(host='localhost', user='user', password='pass', database='ha')
cursor = conn.cursor()
cursor.execute("""
    SELECT FROM_UNIXTIME(start_ts) as hour,
           mean, sum
    FROM statistics s
    JOIN statistics_meta sm ON s.metadata_id = sm.id
    WHERE sm.statistic_id = %s
""", ('sensor.linky_urms1',))
```

**Problem:** Different SQL syntax, different connection libraries, different parameter styles (`?` vs `%s`)

------

### **With SQLAlchemy (Database-Agnostic) ✅**

```python
from sqlalchemy import create_engine, select, func
from sqlalchemy.orm import sessionmaker

# Just change this URL to switch databases!
# SQLite:
engine = create_engine('sqlite:////config/home-assistant_v2.db')
# OR MariaDB:
# engine = create_engine('mysql+pymysql://user:pass@localhost/homeassistant')

Session = sessionmaker(bind=engine)
session = Session()

# Query in SQLAlchemy ORM style - works on BOTH databases!
query = session.query(
    func.datetime(Statistics.start_ts, 'unixepoch', 'localtime').label('hour'),
    Statistics.mean,
    Statistics.sum
).join(
    StatisticsMeta, 
    Statistics.metadata_id == StatisticsMeta.id
).filter(
    StatisticsMeta.statistic_id == 'sensor.linky_urms1'
)

results = query.all()
```

**SQLAlchemy automatically:**

- Translates `func.datetime()` to `datetime()` for SQLite
- Translates `func.datetime()` to `FROM_UNIXTIME()` for MariaDB
- Handles parameter escaping correctly for each database
- Manages connections and transactions

------

## **How Home Assistant Uses SQLAlchemy**

### **Configuration:**

```yaml
# configuration.yaml
recorder:
  # Just change this one line to switch databases!
  
  # SQLite (default):
  db_url: sqlite:////config/home-assistant_v2.db
  
  # OR MariaDB:
  # db_url: mysql://user:password@localhost/homeassistant
  
  # OR PostgreSQL:
  # db_url: postgresql://user:password@localhost/homeassistant
```

### **Home Assistant's Code:**

```python
# Simplified example from HA source code
from sqlalchemy import create_engine
from homeassistant.components.recorder.models import States, StatisticsMeta

# HA reads the db_url from config
engine = create_engine(config['recorder']['db_url'])

# Same code works regardless of database backend!
query = session.query(States).filter(
    States.entity_id == 'sensor.temperature'
).order_by(States.last_updated.desc()).limit(100)

results = query.all()
```

**The same Python code works whether you're using SQLite, MySQL, or PostgreSQL!**

------

## **SQLAlchemy's Two Levels**

### **1. SQLAlchemy Core (Lower Level)**

Direct SQL-like queries, but database-agnostic:

```python
from sqlalchemy import Table, Column, Integer, String, MetaData, select

metadata = MetaData()
statistics = Table('statistics', metadata,
    Column('id', Integer, primary_key=True),
    Column('start_ts', Float),
    Column('mean', Float)
)

# Build query
stmt = select([statistics.c.mean]).where(statistics.c.start_ts > 1234567890)

# Execute on any database
result = conn.execute(stmt)
```

### **2. SQLAlchemy ORM (Higher Level)**

Object-oriented, Pythonic:

```python
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship

Base = declarative_base()

class Statistics(Base):
    __tablename__ = 'statistics'
    id = Column(Integer, primary_key=True)
    start_ts = Column(Float)
    mean = Column(Float)
    metadata_id = Column(Integer, ForeignKey('statistics_meta.id'))
    
    # Relationship
    meta = relationship("StatisticsMeta")

# Query like Python objects
recent_stats = session.query(Statistics).filter(
    Statistics.start_ts > 1234567890
).all()

for stat in recent_stats:
    print(stat.mean, stat.meta.statistic_id)
```

------

## **Home Assistant's Database Models**

Home Assistant defines models like this (simplified from actual code):

```python
# homeassistant/components/recorder/models.py
from sqlalchemy import Column, Integer, String, Float, ForeignKey
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class StatisticsMeta(Base):
    __tablename__ = "statistics_meta"
    
    id = Column(Integer, primary_key=True)
    statistic_id = Column(String(255))
    source = Column(String(32))
    unit_of_measurement = Column(String(255))
    mean_type = Column(Integer)
    has_sum = Column(Boolean)

class Statistics(Base):
    __tablename__ = "statistics"
    
    id = Column(Integer, primary_key=True)
    metadata_id = Column(Integer, ForeignKey('statistics_meta.id'))
    start_ts = Column(Float)
    mean = Column(Float)
    min = Column(Float)
    max = Column(Float)
    sum = Column(Float)
    state = Column(Float)
```

**Then queries work on any database:**

```python
# Get statistics for a sensor
stats = session.query(Statistics).join(StatisticsMeta).filter(
    StatisticsMeta.statistic_id == 'sensor.linky_urms1',
    Statistics.start_ts >= yesterday_timestamp
).all()
```

------

## **Benefits for Home Assistant**

### **1. User Choice:**

Users can pick their database without HA code changing:

- SQLite for simplicity
- MariaDB for performance
- PostgreSQL for advanced features

### **2. Easy Migration:**

```bash
# Backup SQLite
cp home-assistant_v2.db backup.db

# Change config to MariaDB
# Restart HA
# HA automatically creates tables in MariaDB with the same schema!
```

### **3. Maintainability:**

HA developers write Python, not SQL strings:

```python
# Easy to read and maintain
query = session.query(States).filter(
    States.entity_id.like('sensor.%')
).order_by(States.last_updated.desc())
```

Instead of:

```python
# Hard to maintain, database-specific
if db_type == 'sqlite':
    cursor.execute("SELECT * FROM states WHERE entity_id LIKE ? ORDER BY last_updated DESC", ('sensor.%',))
elif db_type == 'mysql':
    cursor.execute("SELECT * FROM states WHERE entity_id LIKE %s ORDER BY last_updated DESC", ('sensor.%',))
```

------

## **Other Python Projects Using SQLAlchemy**

- **Flask-SQLAlchemy** (web framework)
- **FastAPI** with SQLAlchemy
- **Alembic** (database migrations)
- **Airflow** (data pipelines)
- **Superset** (data visualization)

It's the de facto standard for Python database abstraction!

------

## **Summary**

✅ **Yes, this is exactly why Python apps use SQLAlchemy!**

**Problems SQLAlchemy solves:**

1. Different SQL dialects (SQLite vs MySQL vs PostgreSQL)
2. Different connection libraries
3. Different parameter styles
4. Schema management
5. Database migrations

**Benefits:**

- Write once, run anywhere (database-wise)
- Pythonic, object-oriented queries
- Automatic SQL translation
- Better security (SQL injection prevention)
- Easier testing (mock databases)

**Your observation is spot-on** - SQLAlchemy exists precisely because SQL is NOT universal! 🎯

Home Assistant uses it so users can choose SQLite (simple) or MariaDB/PostgreSQL (performance) without the HA developers maintaining separate codebases.

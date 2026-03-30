from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from usr.database.base import Base

class Existencia(Base):
    __tablename__ = "existencias"
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=True)
    almacen = Column(String(50), nullable=False)
    cantidad = Column(Float, default=0)
    unidad = Column(String(50), default="unidad")

    producto = relationship("Producto", primaryjoin="Existencia.producto_id==Producto.id", viewonly=True)

    def __repr__(self):
        return f"<Existencia(producto_id={self.producto_id}, almacen='{self.almacen}', cantidad={self.cantidad})>"

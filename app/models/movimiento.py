from sqlalchemy import Column, Integer, String, Float, Boolean, ForeignKey, DateTime, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.database.base import Base


class Movimiento(Base):
    __tablename__ = "movimientos"

    id = Column(Integer, primary_key=True, index=True)
    
    # Relación con producto
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)
    producto = relationship("Producto", back_populates="movimientos")
    
    # Relación con factura (opcional, solo para entradas)
    factura_id = Column(Integer, ForeignKey("facturas.id"), nullable=True)
    factura = relationship("Factura", back_populates="movimientos")
    
    # Tipo de movimiento
    tipo = Column(String(10), nullable=False, comment="entrada, salida, ajuste")
    
    # Cantidad
    cantidad = Column(Float, nullable=False)
    cantidad_anterior = Column(Float, default=0)
    cantidad_nueva = Column(Float, default=0)
    
    # Información de peso (para productos que requieren foto)
    peso_registrado = Column(Float, nullable=True, comment="Peso en kg registrado de la balanza")
    foto_peso_url = Column(String(500), nullable=True, comment="Ruta o URL de la foto de la balanza")
    
    # Responsable
    registrado_por = Column(String(100), nullable=False)
    
    # Observaciones
    observaciones = Column(Text, nullable=True)
    
    # Fecha del movimiento
    fecha_movimiento = Column(DateTime(timezone=True), server_default=func.now())
    
    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    def __repr__(self):
        return f"<Movimiento(id={self.id}, tipo='{self.tipo}', cantidad={self.cantidad})>"
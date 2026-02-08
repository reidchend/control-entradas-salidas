from sqlalchemy import Column, Integer, String, DateTime, Float, Boolean, Text, ForeignKey
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.database.base import Base


class Factura(Base):
    __tablename__ = "facturas"

    id = Column(Integer, primary_key=True, index=True)
    numero_factura = Column(String(50), nullable=False, index=True)
    proveedor = Column(String(200), nullable=True)
    
    # Fecha de la factura
    fecha_factura = Column(DateTime(timezone=True), nullable=False)
    fecha_recepcion = Column(DateTime(timezone=True), server_default=func.now())
    
    # Totales
    total_bruto = Column(Float, default=0)
    total_impuestos = Column(Float, default=0)
    total_neto = Column(Float, default=0)
    
    # Estado de la factura
    estado = Column(String(20), default="Pendiente", comment="Pendiente, Validada, Anulada")
    
    # Observaciones
    observaciones = Column(Text, nullable=True)
    
    # Validación
    validada_por = Column(String(100), nullable=True)
    fecha_validacion = Column(DateTime(timezone=True), nullable=True)
    
    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    
    # Relación con movimientos
    movimientos = relationship("Movimiento", back_populates="factura")

    def __repr__(self):
        return f"<Factura(id={self.id}, numero='{self.numero_factura}', estado='{self.estado}')>"
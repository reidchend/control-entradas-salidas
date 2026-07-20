from sqlalchemy import Column, Integer, String, Float, Boolean, ForeignKey, DateTime, Text
from sqlalchemy.sql import func
from usr.database.base import Base


class MovimientoArchivo(Base):
    __tablename__ = "movimientos_archivo"
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)
    factura_id = Column(Integer, ForeignKey("facturas.id"), nullable=True)
    tipo = Column(String(10), nullable=False, comment="entrada, salida, ajuste")
    cantidad = Column(Float, nullable=False)
    cantidad_anterior = Column(Float, default=0)
    cantidad_nueva = Column(Float, default=0)
    peso_total = Column(Float, default=0.0)
    peso_registrado = Column(Float, nullable=True)
    foto_peso_url = Column(String(500), nullable=True)
    registrado_por = Column(String(100), nullable=False)
    observaciones = Column(Text, nullable=True)
    almacen = Column(String(50), nullable=True)
    fecha_movimiento = Column(DateTime(timezone=True), server_default=func.now())
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    def __repr__(self):
        return f"<MovimientoArchivo(id={self.id}, tipo='{self.tipo}', cantidad={self.cantidad})>"
